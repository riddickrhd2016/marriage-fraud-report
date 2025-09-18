from __future__ import annotations

from flask import Flask, render_template

from .data_loader import load_all_data, load_evidence_index, load_timeline, summarize_evidence, summarize_timeline


def create_app() -> Flask:
    app = Flask(
        __name__,
        template_folder="templates",
        static_folder="static",
    )

    @app.context_processor
    def inject_globals():
        data = load_all_data()
        return {
            "evidence_summary": data["evidence_summary"],
            "timeline_summary": data["timeline_summary"],
        }

    @app.route("/")
    def index():
        evidence = load_evidence_index()
        timeline = load_timeline()
        return render_template(
            "index.html",
            evidence_summary=summarize_evidence(evidence),
            timeline_summary=summarize_timeline(timeline),
        )

    @app.route("/evidence")
    def evidence():
        evidence_records = load_evidence_index()
        return render_template("evidence.html", records=evidence_records)

    @app.route("/timeline")
    def timeline():
        timeline_entries = load_timeline()
        return render_template("timeline.html", entries=timeline_entries)

    return app


def main() -> None:
    app = create_app()
    app.run(host="0.0.0.0", port=5000, debug=True)


if __name__ == "__main__":
    main()
