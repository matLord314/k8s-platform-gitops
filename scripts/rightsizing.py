#!/usr/bin/env python3
"""Compare requests with CPU and memory usage.

Below 30% of the request is over-requested, above 90% is under-requested.
Missing requests are called out on their own.

Reads the metrics API, a Prometheus URL, or a JSON fixture.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass

OVER_REQUESTED = 0.30
UNDER_REQUESTED = 0.90

_BINARY_UNITS = {
    "Ki": 1024,
    "Mi": 1024**2,
    "Gi": 1024**3,
    "Ti": 1024**4,
    "Pi": 1024**5,
    "Ei": 1024**6,
}
_DECIMAL_UNITS = {
    "k": 1000,
    "M": 1000**2,
    "G": 1000**3,
    "T": 1000**4,
    "P": 1000**5,
    "E": 1000**6,
}


@dataclass
class Sample:
    namespace: str
    pod: str
    container: str
    cpu_request_m: float | None
    mem_request: int | None
    cpu_usage_m: float | None
    mem_usage: int | None


@dataclass
class Row:
    sample: Sample
    cpu_ratio: float | None
    mem_ratio: float | None
    cpu_status: str
    mem_status: str


def parse_cpu(quantity: str) -> float:
    """CPU quantity as millicores."""
    value = quantity.strip()
    if value.endswith("n"):
        return float(value[:-1]) / 1_000_000
    if value.endswith("u"):
        return float(value[:-1]) / 1_000
    if value.endswith("m"):
        return float(value[:-1])
    return float(value) * 1000


def parse_memory(quantity: str) -> int:
    """Memory quantity as bytes."""
    value = quantity.strip()
    for suffix, factor in _BINARY_UNITS.items():
        if value.endswith(suffix):
            return int(float(value[: -len(suffix)]) * factor)
    for suffix, factor in _DECIMAL_UNITS.items():
        if value.endswith(suffix):
            return int(float(value[: -len(suffix)]) * factor)
    return int(float(value))


def _optional_cpu(quantities: dict, key: str) -> float | None:
    raw = quantities.get(key)
    if raw in (None, ""):
        return None
    return parse_cpu(str(raw))


def _optional_memory(quantities: dict, key: str) -> int | None:
    raw = quantities.get(key)
    if raw in (None, ""):
        return None
    return parse_memory(str(raw))


def status_for(request: float | None, usage: float | None) -> str:
    if request is None or request <= 0:
        return "missing-request"
    if usage is None:
        return "no-data"
    ratio = usage / request
    if ratio < OVER_REQUESTED:
        return "over-requested"
    if ratio > UNDER_REQUESTED:
        return "under-requested"
    return "ok"


def ratio_for(request: float | None, usage: float | None) -> float | None:
    if request is None or request <= 0 or usage is None:
        return None
    return usage / request


def evaluate(samples: list[Sample]) -> list[Row]:
    rows: list[Row] = []
    for sample in samples:
        rows.append(
            Row(
                sample=sample,
                cpu_ratio=ratio_for(sample.cpu_request_m, sample.cpu_usage_m),
                mem_ratio=ratio_for(sample.mem_request, sample.mem_usage),
                cpu_status=status_for(sample.cpu_request_m, sample.cpu_usage_m),
                mem_status=status_for(sample.mem_request, sample.mem_usage),
            )
        )
    return rows


def samples_from_fixture(payload: dict) -> list[Sample]:
    samples: list[Sample] = []
    for pod in payload["pods"]:
        for container in pod["containers"]:
            requests = container.get("requests") or {}
            usage = container.get("usage") or {}
            samples.append(
                Sample(
                    namespace=pod["namespace"],
                    pod=pod["name"],
                    container=container["name"],
                    cpu_request_m=_optional_cpu(requests, "cpu"),
                    mem_request=_optional_memory(requests, "memory"),
                    cpu_usage_m=_optional_cpu(usage, "cpu"),
                    mem_usage=_optional_memory(usage, "memory"),
                )
            )
    return samples


def _kubectl_json(args: list[str]) -> dict:
    try:
        completed = subprocess.run(
            ["kubectl", *args],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("kubectl is not installed") from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        raise RuntimeError(detail or "kubectl failed") from exc
    return json.loads(completed.stdout)


def samples_from_cluster(namespace: str | None) -> list[Sample]:
    pod_args = ["get", "pods", "-o", "json"]
    if namespace:
        pod_args[2:2] = ["-n", namespace]
    else:
        pod_args[2:2] = ["-A"]
    pods = _kubectl_json(pod_args)
    metrics = _kubectl_json(["get", "--raw", "/apis/metrics.k8s.io/v1beta1/pods"])
    usage_index: dict[tuple[str, str, str], dict] = {}
    for item in metrics.get("items", []):
        meta = item["metadata"]
        for container in item.get("containers", []):
            key = (meta["namespace"], meta["name"], container["name"])
            usage_index[key] = container.get("usage") or {}

    samples: list[Sample] = []
    for pod in pods.get("items", []):
        if pod.get("status", {}).get("phase") != "Running":
            continue
        meta = pod["metadata"]
        if namespace and meta["namespace"] != namespace:
            continue
        for container in pod["spec"].get("containers", []):
            requests = container.get("resources", {}).get("requests") or {}
            usage = usage_index.get((meta["namespace"], meta["name"], container["name"]), {})
            samples.append(
                Sample(
                    namespace=meta["namespace"],
                    pod=meta["name"],
                    container=container["name"],
                    cpu_request_m=_optional_cpu(requests, "cpu"),
                    mem_request=_optional_memory(requests, "memory"),
                    cpu_usage_m=_optional_cpu(usage, "cpu"),
                    mem_usage=_optional_memory(usage, "memory"),
                )
            )
    return samples


def _prometheus_vector(base_url: str, query: str) -> list[dict]:
    endpoint = base_url.rstrip("/") + "/api/v1/query"
    url = endpoint + "?" + urllib.parse.urlencode({"query": query})
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            payload = json.load(response)
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Prometheus query failed: {exc}") from exc
    if payload.get("status") != "success":
        raise RuntimeError(f"Prometheus returned {payload.get('status')}")
    return payload["data"]["result"]


def samples_from_prometheus(base_url: str, namespace: str | None) -> list[Sample]:
    ns = f',namespace="{namespace}"' if namespace else ""
    cpu_req = _prometheus_vector(
        base_url,
        "kube_pod_container_resource_requests"
        f'{{resource="cpu",container!=""{ns}}}',
    )
    mem_req = _prometheus_vector(
        base_url,
        "kube_pod_container_resource_requests"
        f'{{resource="memory",container!=""{ns}}}',
    )
    cpu_use = _prometheus_vector(
        base_url,
        "sum by (namespace, pod, container) "
        "(rate(container_cpu_usage_seconds_total"
        f'{{container!="",container!="POD"{ns}}}[5m]))',
    )
    mem_use = _prometheus_vector(
        base_url,
        "sum by (namespace, pod, container) "
        "(container_memory_working_set_bytes"
        f'{{container!="",container!="POD"{ns}}})',
    )
    return samples_from_series(cpu_req, mem_req, cpu_use, mem_use)


def _series_value(item: dict) -> float:
    return float(item["value"][1])


def samples_from_series(
    cpu_requests: list[dict],
    mem_requests: list[dict],
    cpu_usage: list[dict],
    mem_usage: list[dict],
) -> list[Sample]:
    """Join Prometheus vectors on namespace, pod and container."""
    index: dict[tuple[str, str, str], dict] = {}

    def slot(item: dict) -> dict:
        metric = item["metric"]
        key = (metric["namespace"], metric["pod"], metric["container"])
        return index.setdefault(key, {})

    for item in cpu_requests:
        slot(item)["cpu_request_m"] = _series_value(item) * 1000
    for item in mem_requests:
        slot(item)["mem_request"] = int(_series_value(item))
    for item in cpu_usage:
        slot(item)["cpu_usage_m"] = _series_value(item) * 1000
    for item in mem_usage:
        slot(item)["mem_usage"] = int(_series_value(item))

    samples: list[Sample] = []
    for (namespace, pod, container), values in sorted(index.items()):
        samples.append(
            Sample(
                namespace=namespace,
                pod=pod,
                container=container,
                cpu_request_m=values.get("cpu_request_m"),
                mem_request=values.get("mem_request"),
                cpu_usage_m=values.get("cpu_usage_m"),
                mem_usage=values.get("mem_usage"),
            )
        )
    return samples


def format_cpu(millicores: float | None) -> str:
    if millicores is None:
        return "-"
    if abs(millicores) >= 1000:
        return f"{millicores / 1000:.2f}"
    return f"{millicores:.0f}m"


def format_memory(num_bytes: int | None) -> str:
    if num_bytes is None:
        return "-"
    mib = num_bytes / (1024**2)
    if abs(mib) >= 1024:
        return f"{mib / 1024:.2f}Gi"
    return f"{mib:.0f}Mi"


def format_ratio(ratio: float | None) -> str:
    if ratio is None:
        return "-"
    return f"{ratio:.2f}"


def render_text(rows: list[Row]) -> str:
    header = (
        "NAMESPACE",
        "POD",
        "CONTAINER",
        "RESOURCE",
        "REQUEST",
        "USAGE",
        "RATIO",
        "STATUS",
    )
    body: list[tuple[str, ...]] = []
    for row in rows:
        sample = row.sample
        body.append(
            (
                sample.namespace,
                sample.pod,
                sample.container,
                "cpu",
                format_cpu(sample.cpu_request_m),
                format_cpu(sample.cpu_usage_m),
                format_ratio(row.cpu_ratio),
                row.cpu_status,
            )
        )
        body.append(
            (
                sample.namespace,
                sample.pod,
                sample.container,
                "memory",
                format_memory(sample.mem_request),
                format_memory(sample.mem_usage),
                format_ratio(row.mem_ratio),
                row.mem_status,
            )
        )
    widths = [len(column) for column in header]
    for record in body:
        for index, column in enumerate(record):
            widths[index] = max(widths[index], len(column))
    lines = ["  ".join(column.ljust(widths[index]) for index, column in enumerate(header))]
    for record in body:
        lines.append(
            "  ".join(column.ljust(widths[index]) for index, column in enumerate(record))
        )
    counts: dict[str, int] = {}
    for row in rows:
        for state in (row.cpu_status, row.mem_status):
            counts[state] = counts.get(state, 0) + 1
    summary = ", ".join(f"{count} {name}" for name, count in sorted(counts.items()))
    lines.append(f"{len(rows)} containers: {summary}")
    return "\n".join(lines)


def render_json(rows: list[Row]) -> str:
    payload = []
    for row in rows:
        sample = row.sample
        payload.append(
            {
                "namespace": sample.namespace,
                "pod": sample.pod,
                "container": sample.container,
                "cpu": {
                    "request_millicores": sample.cpu_request_m,
                    "usage_millicores": sample.cpu_usage_m,
                    "ratio": row.cpu_ratio,
                    "status": row.cpu_status,
                },
                "memory": {
                    "request_bytes": sample.mem_request,
                    "usage_bytes": sample.mem_usage,
                    "ratio": row.mem_ratio,
                    "status": row.mem_status,
                },
            }
        )
    return json.dumps(payload, indent=2)


def strict_problems(rows: list[Row]) -> list[str]:
    problems = []
    for row in rows:
        sample = row.sample
        name = f"{sample.namespace}/{sample.pod}/{sample.container}"
        for resource, state in (("cpu", row.cpu_status), ("memory", row.mem_status)):
            if state in {"under-requested", "missing-request"}:
                problems.append(f"{name} {resource} {state}")
    return problems


def self_test() -> int:
    cpu_low = status_for(100, 5)
    mem_high = status_for(64 * 1024**2, 62 * 1024**2)
    missing = status_for(None, 20)
    ok = status_for(128, 50)
    expected = {
        "over-requested": cpu_low,
        "under-requested": mem_high,
        "missing-request": missing,
        "ok": ok,
    }
    failed = [name for name, got in expected.items() if got != name]
    series = samples_from_series(
        cpu_requests=[
            {
                "metric": {"namespace": "demo", "pod": "p", "container": "app"},
                "value": [0, "0.1"],
            }
        ],
        mem_requests=[
            {
                "metric": {"namespace": "demo", "pod": "p", "container": "app"},
                "value": [0, str(128 * 1024**2)],
            }
        ],
        cpu_usage=[
            {
                "metric": {"namespace": "demo", "pod": "p", "container": "app"},
                "value": [0, "0.005"],
            }
        ],
        mem_usage=[
            {
                "metric": {"namespace": "demo", "pod": "p", "container": "app"},
                "value": [0, str(40 * 1024**2)],
            }
        ],
    )
    rows = evaluate(series)
    if len(rows) != 1 or rows[0].cpu_status != "over-requested":
        failed.append("prometheus-join")
    if rows and rows[0].mem_status != "ok":
        failed.append("prometheus-memory")
    if failed:
        print("self-test failed: " + ", ".join(failed), file=sys.stderr)
        return 1
    print("self-test passed")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare CPU and memory requests with usage."
    )
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--fixture", help="JSON with requests and usage")
    source.add_argument("--prometheus-url", help="Prometheus base URL")
    parser.add_argument("--namespace", help="only this namespace")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="exit 1 on under-requested or missing requests",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run the built-in checks",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        return self_test()
    try:
        if args.fixture:
            with open(args.fixture, encoding="utf-8") as handle:
                samples = samples_from_fixture(json.load(handle))
        elif args.prometheus_url:
            samples = samples_from_prometheus(args.prometheus_url, args.namespace)
        else:
            samples = samples_from_cluster(args.namespace)
    except (OSError, RuntimeError, KeyError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.namespace and args.fixture:
        samples = [sample for sample in samples if sample.namespace == args.namespace]
    rows = evaluate(samples)
    rendered = render_json(rows) if args.format == "json" else render_text(rows)
    print(rendered)
    if args.strict and strict_problems(rows):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
