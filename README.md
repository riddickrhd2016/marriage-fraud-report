# Marriage Fraud Reporting Workspace

This workspace helps you organize a clear report with indexed evidence for submission to ICE/HSI and USCIS.

Contents:

- 01-report: main report
- 02-evidence: raw and redacted evidence
- 03-correspondence: cover letters
- 04-logs: evidence index and hashes
- 05-exports: packaged zip for submission
- 06-legal: affidavit template and any legal notes

Notes:

- This is general information, not legal advice. Agencies may still contact you.
- Protect sensitive data. Place only redacted files in '02-evidence/redacted' for submission.

## Timeline tooling

- Fill `02-evidence/raw/E-004-TimelineDocs/Transcript-template.md` and save as `Transcript.md` in the same folder.
- Parse your transcript to CSV:

  ```powershell
  .\scripts\parse-transcript.ps1 -TranscriptPath '.\02-evidence\raw\E-004-TimelineDocs\Transcript.md' -OutCsv '.\04-logs\transcript-chronology.csv'
  ```
- Merge with screenshots chronology (after running OCR script):

  ```powershell
  .\scripts\merge-chronology.ps1 -ScreenshotChronoCsv '.\04-logs\screenshots-chronology.csv' -TranscriptChronoCsv '.\04-logs\transcript-chronology.csv' -OutCsv '.\04-logs\master-chronology.csv'
  ```
## Dashboard web app

A lightweight Flask dashboard is available under `app/`. It reads the CSV logs in
`04-logs` to provide a quick overview of evidence and chronology data.

### Setup

1. Create a virtual environment and install dependencies:

   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. Run the development server:

   ```bash
   flask --app app.app --debug run
   ```

   The dashboard is served on <http://localhost:5000/>.

### Features

- Overview card summarizing evidence sources and timeline buckets.
- Searchable evidence index table with responsive layout.
- Timeline table with toggle to show only flagged events.
- Automatic refresh of data whenever the CSV files in `04-logs` change.
