"""
StreamFlow Provenance Dashboard
Visualises benchmark data and provenance from StreamFlow CWL workflow runs.
Data sources:
  - results/**/iot_report.json   (IoT pipeline output with per-device stats)
  - .streamflow/sqlite.db        (provenance: steps, commands, DAG)
  - Hardcoded benchmark table     (wall-clock times from notes/benchmarks.md)
"""

import json
import sqlite3
from pathlib import Path

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RESULTS_DIR = PROJECT_ROOT / "results"
SQLITE_DB = PROJECT_ROOT / ".streamflow" / "sqlite.db"

# ── Benchmark data (canonical, from notes/benchmarks.md) ─────────────────────

BENCHMARKS = pd.DataFrame([
    {"workflow": "Hello (4 tasks)", "swms": "StreamFlow", "deployment": "local", "wall_clock_s": 2.7},
    {"workflow": "Hello (4 tasks)", "swms": "StreamFlow", "deployment": "docker", "wall_clock_s": 7.5},
    {"workflow": "Mini-pipeline (5+1)", "swms": "StreamFlow", "deployment": "docker", "wall_clock_s": 15.2},
    {"workflow": "IoT (10x10K)", "swms": "StreamFlow", "deployment": "docker", "wall_clock_s": 29.6},
    {"workflow": "IoT (10x10K)", "swms": "StreamFlow", "deployment": "k8s all-cloud", "wall_clock_s": 24.6},
    {"workflow": "IoT (10x10K)", "swms": "StreamFlow", "deployment": "k8s continuum", "wall_clock_s": 24.2},
    {"workflow": "IoT (10x10K)", "swms": "StreamFlow", "deployment": "k8s cloud-only", "wall_clock_s": 23.6},
    {"workflow": "IoT (10x10K)", "swms": "StreamFlow", "deployment": "k8s latency 200ms", "wall_clock_s": 26.3},
    {"workflow": "IoT (10x10K)", "swms": "StreamFlow", "deployment": "k8s latency 500ms", "wall_clock_s": 32.3},
    {"workflow": "IoT (50x100K)", "swms": "Nextflow", "deployment": "docker", "wall_clock_s": 457.0},
    {"workflow": "IoT (50x100K)", "swms": "Nextflow", "deployment": "k8s (k3d)", "wall_clock_s": 115.0},
])

LATENCY_DATA = pd.DataFrame([
    {"latency_ms": 0, "wall_clock_s": 23.9, "per_device_overhead_s": 0.0},
    {"latency_ms": 200, "wall_clock_s": 26.3, "per_device_overhead_s": 0.4},
    {"latency_ms": 500, "wall_clock_s": 32.3, "per_device_overhead_s": 1.0},
])


# ── Data loaders ─────────────────────────────────────────────────────────────

@st.cache_data
def load_iot_reports():
    """Scan results/ for iot_report.json files and return a dict keyed by run name."""
    reports = {}
    if not RESULTS_DIR.exists():
        return reports
    for report_path in sorted(RESULTS_DIR.rglob("iot_report.json")):
        parts = report_path.relative_to(RESULTS_DIR).parts
        run_name = parts[0]  # e.g. "iot_k8s_continuum"
        with open(report_path) as f:
            reports[run_name] = json.load(f)
    return reports


@st.cache_data
def load_provenance():
    """Load step, command, and dependency data from StreamFlow's SQLite DB."""
    if not SQLITE_DB.exists():
        return None, None, None
    conn = sqlite3.connect(SQLITE_DB)
    steps = pd.read_sql("SELECT * FROM step", conn)
    commands = pd.read_sql("""
        SELECT c.id, s.name as step_name, c.cmd, c.status,
               c.start_time / 1e9 as start_epoch,
               c.end_time / 1e9   as end_epoch,
               (c.end_time - c.start_time) / 1e6 as duration_ms
        FROM command c JOIN step s ON c.step = s.id
        ORDER BY c.start_time
    """, conn)
    deps = pd.read_sql("""
        SELECT d1.name as source, d2.name as target
        FROM dependency dep
        JOIN step d1 ON dep.dependee = d1.id
        JOIN step d2 ON dep.depender = d2.id
    """, conn)
    conn.close()
    return steps, commands, deps


# ── Page config ──────────────────────────────────────────────────────────────

st.set_page_config(
    page_title="StreamFlow Provenance Dashboard",
    page_icon="🔬",
    layout="wide",
)

st.title("StreamFlow Provenance Dashboard")
st.caption("IoT-Edge-Cloud Continuum — Workflow Benchmarks & Provenance")

tab_bench, tab_latency, tab_gantt, tab_iot, tab_dag = st.tabs([
    "Benchmarks", "Latency Analysis", "Execution Timeline", "IoT Sensor Data", "Workflow DAG"
])

# ── Tab 1: Benchmarks ────────────────────────────────────────────────────────

with tab_bench:
    st.header("Cross-SWMS Benchmark Comparison")

    col1, col2 = st.columns([2, 1])

    with col1:
        iot_only = BENCHMARKS[BENCHMARKS["workflow"].str.startswith("IoT")]
        fig = px.bar(
            iot_only,
            x="deployment",
            y="wall_clock_s",
            color="swms",
            barmode="group",
            title="IoT Pipeline — Wall-Clock Time by Deployment",
            labels={"wall_clock_s": "Wall-clock (s)", "deployment": "Deployment"},
            color_discrete_map={"StreamFlow": "#1f77b4", "Nextflow": "#ff7f0e"},
        )
        fig.update_layout(xaxis_tickangle=-30, height=450)
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.subheader("All Runs")
        st.dataframe(
            BENCHMARKS.style.format({"wall_clock_s": "{:.1f}"}),
            hide_index=True,
            use_container_width=True,
        )

    st.divider()

    sf_iot = BENCHMARKS[
        (BENCHMARKS["swms"] == "StreamFlow") & (BENCHMARKS["workflow"] == "IoT (10x10K)")
    ].copy()

    if not sf_iot.empty:
        fig2 = px.bar(
            sf_iot.sort_values("wall_clock_s"),
            x="wall_clock_s",
            y="deployment",
            orientation="h",
            title="StreamFlow IoT (10x10K) — Deployment Comparison",
            labels={"wall_clock_s": "Wall-clock (s)", "deployment": ""},
            color="wall_clock_s",
            color_continuous_scale="Blues",
        )
        fig2.update_layout(height=350, showlegend=False)
        st.plotly_chart(fig2, use_container_width=True)

# ── Tab 2: Latency Analysis ──────────────────────────────────────────────────

with tab_latency:
    st.header("WAN Latency Impact on Continuum Execution")

    col1, col2 = st.columns(2)

    with col1:
        fig = go.Figure()
        fig.add_trace(go.Scatter(
            x=LATENCY_DATA["latency_ms"],
            y=LATENCY_DATA["wall_clock_s"],
            mode="lines+markers+text",
            text=[f"{v:.1f}s" for v in LATENCY_DATA["wall_clock_s"]],
            textposition="top center",
            name="Wall-clock",
            line=dict(color="#1f77b4", width=3),
            marker=dict(size=12),
        ))
        fig.update_layout(
            title="Wall-Clock Time vs. Simulated WAN Latency",
            xaxis_title="Transfer Latency per Hop (ms)",
            yaxis_title="Total Wall-Clock (s)",
            height=400,
        )
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        sequential_overhead = LATENCY_DATA.copy()
        sequential_overhead["total_overhead_s"] = (
            sequential_overhead["latency_ms"] / 1000 * 2 * 10
        )
        sequential_overhead["parallel_overhead_s"] = (
            sequential_overhead["latency_ms"] / 1000 * 2
        )

        fig2 = go.Figure()
        fig2.add_trace(go.Bar(
            x=[f"{l}ms" for l in sequential_overhead["latency_ms"]],
            y=sequential_overhead["total_overhead_s"],
            name="Sequential (StreamFlow)",
            marker_color="#e74c3c",
        ))
        fig2.add_trace(go.Bar(
            x=[f"{l}ms" for l in sequential_overhead["latency_ms"]],
            y=sequential_overhead["parallel_overhead_s"],
            name="Parallel (ideal)",
            marker_color="#2ecc71",
        ))
        fig2.update_layout(
            title="Latency Overhead: Sequential vs. Parallel Scatter",
            xaxis_title="Transfer Latency",
            yaxis_title="Total Latency Overhead (s)",
            barmode="group",
            height=400,
        )
        st.plotly_chart(fig2, use_container_width=True)

    st.info(
        "**Key finding**: With sequential scatter (StreamFlow 0.1.6), latency overhead "
        "scales as `N_devices x 2 x latency`. Parallel execution would reduce this to "
        "`2 x latency` regardless of device count — a **10x reduction** for 10 devices."
    )

    st.subheader("Latency Breakdown")
    st.dataframe(
        LATENCY_DATA.rename(columns={
            "latency_ms": "Latency (ms)",
            "wall_clock_s": "Wall-Clock (s)",
            "per_device_overhead_s": "Per-Device Overhead (s)",
        }).style.format({
            "Wall-Clock (s)": "{:.1f}",
            "Per-Device Overhead (s)": "{:.1f}",
        }),
        hide_index=True,
    )

# ── Tab 3: Execution Timeline (Gantt from SQLite) ────────────────────────────

with tab_gantt:
    st.header("Execution Timeline (Last Run)")

    steps, commands, deps = load_provenance()

    if commands is not None and not commands.empty:
        min_epoch = commands["start_epoch"].min()
        commands["start_rel"] = commands["start_epoch"] - min_epoch
        commands["end_rel"] = commands["end_epoch"] - min_epoch

        gantt_df = commands.copy()
        gantt_df["start"] = pd.to_datetime(gantt_df["start_epoch"], unit="s")
        gantt_df["end"] = pd.to_datetime(gantt_df["end_epoch"], unit="s")
        gantt_df["label"] = gantt_df["step_name"].str.replace("/", "")

        fig = px.timeline(
            gantt_df,
            x_start="start",
            x_end="end",
            y="label",
            color="label",
            title="Task Execution Gantt Chart (from StreamFlow provenance DB)",
            labels={"label": "Step"},
        )
        fig.update_layout(
            height=max(300, len(gantt_df) * 35),
            showlegend=False,
            yaxis_title="",
        )
        st.plotly_chart(fig, use_container_width=True)

        st.subheader("Command Details")
        display_df = commands[["id", "step_name", "duration_ms", "status"]].copy()
        display_df["duration_s"] = display_df["duration_ms"] / 1000
        display_df["status"] = display_df["status"].map({4: "COMPLETED", 6: "FAILED"}).fillna("UNKNOWN")
        st.dataframe(
            display_df[["id", "step_name", "duration_s", "status"]].rename(columns={
                "id": "Command ID",
                "step_name": "Step",
                "duration_s": "Duration (s)",
                "status": "Status",
            }).style.format({"Duration (s)": "{:.3f}"}),
            hide_index=True,
            use_container_width=True,
        )

        total_s = (commands["end_epoch"].max() - commands["start_epoch"].min())
        compute_s = commands["duration_ms"].sum() / 1000
        st.metric("Total wall-clock", f"{total_s:.1f}s")
        col1, col2 = st.columns(2)
        col1.metric("Sum of task durations", f"{compute_s:.1f}s")
        col2.metric("Engine overhead", f"{total_s - compute_s:.1f}s")
    else:
        st.warning("No provenance data found. Run a StreamFlow workflow first to populate `.streamflow/sqlite.db`.")

# ── Tab 4: IoT Sensor Data ──────────────────────────────────────────────────

with tab_iot:
    st.header("IoT Pipeline Results")

    reports = load_iot_reports()

    if not reports:
        st.warning("No IoT report JSON files found in results/.")
    else:
        run_name = st.selectbox("Select run", sorted(reports.keys()))
        report = reports[run_name]

        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Devices", report["num_devices"])
        col2.metric("Clean readings", f"{report['total_readings_clean']:,}")
        col3.metric("Anomalies", f"{report['total_anomalies']:,}")
        col4.metric("Anomaly rate", f"{report['anomaly_rate_pct']:.2f}%")

        st.divider()

        devices = report["per_device"]
        dev_df = pd.DataFrame([{
            "device_id": d["device_id"],
            "readings": d["readings_clean"],
            "anomalies": d["anomalies_detected"],
            "temp_mean": d["temperature"]["mean"],
            "temp_stdev": d["temperature"]["stdev"],
            "humidity_mean": d["humidity"]["mean"],
            "pressure_mean": d["pressure"]["mean"],
        } for d in devices]).sort_values("device_id")

        col1, col2 = st.columns(2)

        with col1:
            fig = px.bar(
                dev_df,
                x="device_id",
                y=["readings", "anomalies"],
                title="Readings & Anomalies per Device",
                barmode="group",
                labels={"value": "Count", "device_id": "Device ID"},
            )
            fig.update_layout(height=350)
            st.plotly_chart(fig, use_container_width=True)

        with col2:
            fig = go.Figure()
            fig.add_trace(go.Scatter(
                x=dev_df["device_id"], y=dev_df["temp_mean"],
                error_y=dict(type="data", array=dev_df["temp_stdev"]),
                mode="markers+lines", name="Temperature (C)",
            ))
            fig.update_layout(
                title="Mean Temperature per Device (with stdev)",
                xaxis_title="Device ID",
                yaxis_title="Temperature (C)",
                height=350,
            )
            st.plotly_chart(fig, use_container_width=True)

        has_timing = "timing" in devices[0]
        if has_timing:
            st.subheader("Per-Device Timing Breakdown")
            timing_df = pd.DataFrame([{
                "device_id": d["device_id"],
                "simulate_s": d["timing"]["simulate_s"],
                "preprocess_s": d["timing"]["preprocess_s"],
                "stats_s": d["timing"]["stats_s"],
                "transfer_s": d["timing"]["total_transfer_s"],
                "latency_ms": d["timing"]["transfer_latency_ms"],
            } for d in devices]).sort_values("device_id")

            fig = px.bar(
                timing_df.melt(
                    id_vars=["device_id", "latency_ms"],
                    value_vars=["simulate_s", "preprocess_s", "stats_s", "transfer_s"],
                    var_name="phase", value_name="seconds"
                ),
                x="device_id",
                y="seconds",
                color="phase",
                title=f"Execution Phases per Device (latency={timing_df['latency_ms'].iloc[0]}ms)",
                labels={"seconds": "Time (s)", "device_id": "Device ID"},
            )
            fig.update_layout(height=400)
            st.plotly_chart(fig, use_container_width=True)

        st.subheader("System-Level Statistics")
        sys_df = pd.DataFrame([{
            "Metric": "Temperature (C)",
            "Mean": report["system_temperature"]["mean"],
            "Stdev": report["system_temperature"]["stdev_across_devices"],
        }, {
            "Metric": "Humidity (%)",
            "Mean": report["system_humidity"]["mean"],
            "Stdev": report["system_humidity"]["stdev_across_devices"],
        }, {
            "Metric": "Pressure (hPa)",
            "Mean": report["system_pressure"]["mean"],
            "Stdev": report["system_pressure"]["stdev_across_devices"],
        }])
        st.dataframe(sys_df.style.format({"Mean": "{:.2f}", "Stdev": "{:.2f}"}), hide_index=True)

# ── Tab 5: Workflow DAG ──────────────────────────────────────────────────────

with tab_dag:
    st.header("Workflow DAG (Last Run)")

    steps, commands, deps = load_provenance()

    if deps is not None and not deps.empty:
        try:
            import graphviz

            dot = graphviz.Digraph(comment="StreamFlow Workflow DAG")
            dot.attr(rankdir="TB", bgcolor="transparent")
            dot.attr("node", shape="box", style="rounded,filled", fillcolor="#e8f4fd", fontname="Helvetica")
            dot.attr("edge", color="#1f77b4", penwidth="2")

            all_nodes = set(deps["source"].tolist() + deps["target"].tolist())
            for node in all_nodes:
                label = node.replace("/", "")
                dot.node(node, label)

            for _, row in deps.iterrows():
                dot.edge(row["source"], row["target"])

            st.graphviz_chart(dot)

        except ImportError:
            st.warning("Install `graphviz` Python package for DAG rendering: `pip install graphviz`")
            st.subheader("Dependencies (table)")
            st.dataframe(deps, hide_index=True)
    else:
        st.warning("No dependency data in the provenance DB. Run a multi-step workflow to populate the DAG.")

    if steps is not None and not steps.empty:
        st.subheader("Steps")
        steps_display = steps.copy()
        steps_display["status"] = steps_display["status"].map({4: "COMPLETED", 6: "FAILED"}).fillna("UNKNOWN")
        st.dataframe(steps_display.rename(columns={"id": "ID", "name": "Step Name", "status": "Status"}), hide_index=True)
