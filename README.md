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
