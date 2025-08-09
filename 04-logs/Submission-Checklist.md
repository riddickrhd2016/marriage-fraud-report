# Submission Checklist

- Draft '01-report/Report.md' with dates and specifics
- Populate '04-logs/Evidence-Index.csv'
- Place originals in '02-evidence/raw'
- Create redactions and save to '02-evidence/redacted'
- Run 'scripts/hash-evidence.ps1' to compute hashes
- Run 'scripts/validate-evidence.ps1' to generate validation-report and fix any issues
- Review '03-correspondence' cover letters
- Run 'scripts/package.ps1' to create submission zip
- Submit via official ICE/USCIS channels and keep a copy of confirmations

## Addendum

- [ ] Copy transcript notes into `02-evidence/raw/E-004-TimelineDocs/Transcript.md` using the provided template
- [ ] Run transcript parser to generate `04-logs/transcript-chronology.csv`
- [ ] Run OCR chronology for screenshots (`04-logs/screenshots-chronology.csv`)
- [ ] Merge to `04-logs/master-chronology.csv`
- [ ] Review `ConcernFlag` and exclude or annotate risky items before redaction
