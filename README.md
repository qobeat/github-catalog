# **github-catalog**

A minimalistic, zero-dependency (Bash/jq/git) CLI tool for building an append-only catalog of git repositories. It extracts semantic documentation (Goals, Objectives, Requirements) and commit history without cloning full working trees and without using LLMs.  
This project follows strict OSINT and ADLC principles: deterministic execution, verifiable evidence, and strict environment isolation. Read the architecture specification in [docs/ADR-001-github-catalog-rewrite.md](http://docs.google.com/docs/ADR-001-github-catalog-rewrite.md).

## **Prerequisites**

* **Bash 5.0+** (Required for parallel wait \-n job control)  
* **jq 1.7+** (Required for JSONL stream processing)  
* **git**  
* **gh** (Optional: Only required if using \--refresh to fetch inventory lists from GitHub)

## **Quickstart**

The tool is operated entirely through the github-catalog root executable.

### **1\. Sync Repositories**

Discover and extract data from repositories. The data is appended securely to JSONL ledgers.  
\# Sync all private repos for user 'qobeat', fetching the latest list from GitHub  
./github-catalog sync qobeat '\*' \--private \--refresh

\# Sync a specific project quickly (uses local inventory cache, no gh call)  
./github-catalog sync qobeat 'ados-framework'

### **2\. Generate Reports**

Compile the raw JSONL ledgers into a human-readable Markdown report.  
./github-catalog report qobeat  
\# Output saved to: reports/qobeat/latest.md

## **Data Architecture**

All output is partitioned by the target owner and isolated from version control (.gitignore applied).  
data/\<owner\>/  
  ├── user-repositories.jsonl      \# Discovered inventory (via gh)  
  ├── git-projects-catalog.jsonl   \# Append-only semantic snapshots  
  └── git-projects-commits.jsonl   \# Append-only commit history

reports/\<owner\>/  
  └── latest.md                    \# Generated pure-jq report

### **Schemas**

The JSONL records adhere strictly to docs/github-catalog.schema.json. You can validate the schema logic using:  
jq '.' docs/github-catalog.schema.json

## **Testing & Development**

This repository utilizes a custom, pure-Bash testing framework to ensure zero external dependencies (no Python, no BATS).  
\# Run syntax checks and ShellCheck  
./github-catalog lint

\# Run isolated unit tests  
./github-catalog test  
