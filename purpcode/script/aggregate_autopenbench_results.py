from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-dir", required=True)
    args = parser.parse_args()

    root_dir = Path(args.root_dir).resolve()
    if not root_dir.exists():
        raise FileNotFoundError(root_dir)

    scenario_dirs = sorted(
        path
        for path in root_dir.iterdir()
        if path.is_dir() and path.name[:2].isdigit() and "_" in path.name
    )

    scenarios: list[dict[str, Any]] = []
    total_tasks = 0
    total_success = 0
    total_failed_runs = 0

    for scenario_dir in scenario_dirs:
        exit_code_path = scenario_dir / "exit_code.txt"
        log_path = scenario_dir / "run.log"
        summary_path = scenario_dir / "summary.json"

        exit_code = None
        if exit_code_path.exists():
            exit_code = int(exit_code_path.read_text(encoding="utf-8").strip())

        scenario_summary: dict[str, Any] = {
            "scenario_dir": str(scenario_dir),
            "name": scenario_dir.name,
            "exit_code": exit_code,
            "status": "ok" if exit_code == 0 else "failed",
            "log_path": str(log_path) if log_path.exists() else None,
            "summary_path": str(summary_path) if summary_path.exists() else None,
        }

        if summary_path.exists():
            summary = load_json(summary_path)
            scenario_summary.update(
                {
                    "num_tasks": int(summary.get("num_tasks", 0)),
                    "num_success": int(summary.get("num_success", 0)),
                    "success_rate": float(summary.get("success_rate", 0.0)),
                    "scenarios": summary.get("scenarios", []),
                    "model_path": summary.get("model_path"),
                }
            )
            total_tasks += scenario_summary["num_tasks"]
            total_success += scenario_summary["num_success"]
        else:
            scenario_summary.update(
                {
                    "num_tasks": 0,
                    "num_success": 0,
                    "success_rate": 0.0,
                }
            )

        if exit_code not in (0, None):
            total_failed_runs += 1

        scenarios.append(scenario_summary)

    aggregate = {
        "root_dir": str(root_dir),
        "num_scenarios": len(scenarios),
        "num_failed_runs": total_failed_runs,
        "num_tasks": total_tasks,
        "num_success": total_success,
        "success_rate": (total_success / total_tasks) if total_tasks else 0.0,
        "scenarios": scenarios,
    }

    output_path = root_dir / "aggregate_summary.json"
    with output_path.open("w", encoding="utf-8") as f:
        json.dump(aggregate, f, indent=2, ensure_ascii=False)

    print(json.dumps(aggregate, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
