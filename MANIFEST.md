# **AI Agent Repository Manifest: github-catalog**

**ATTENTION LLM / AGENT:** Read this document immediately upon entering this repository.  
This project is an **Agent Development Lifecycle (ADLC)** compatible tool. It implements a standalone, pure-Bash tool for building an append-only catalog of git repositories, extracting semantic data (Goals, Objectives, Requirements) deterministically without LLM hallucination.

## **1\. Core Directives & Constraints**

* **Architecture Reference:** You MUST adhere to docs/ADR-001-github-catalog-rewrite.md and docs/ADR-002.md.  
* **Zero Core Dependencies:** The engine is strictly restricted to Bash 5.0+, jq 1.7+, and standard git.  
  * **DO NOT** introduce Python, Node.js, BATS, or external APIs to the core execution logic.  
* **The API Bridge:** The gh CLI is *only* permitted inside scripts/github-gh.sh to fetch remote inventory lists. No other script may call gh or network APIs.  
* **Storage:** State is maintained via append-only JSONL files in data/\<user-name\>/. Never rewrite or overwrite existing JSONL lines.

## **2\. The Unified CLI (./github-catalog)**

**Do not call internal scripts in the scripts/ directory directly.** Always use the unified root CLI.

### **Command: sync**

Fetches inventory and appends snapshots/commits.  
\# Sync specific repos, forcing a GitHub API inventory refresh  
./github-catalog sync qobeat 'ados-\*' \--private \--refresh

### **Command: report**

Generates a markdown summary in reports/\<owner\>/latest.md.  
./github-catalog report qobeat

### **Command: test & lint**

Always verify your code modifications using the built-in pure-Bash harness.  
./github-catalog lint  
./github-catalog test

## **3\. Directory Layout**

* github-catalog \- The unified CLI (Primary interface).  
* scripts/ \- Internal pipeline modules (Orchestrator, Fetcher, Reporter, GH-Bridge).  
* tests/ \- Pure-Bash test suite.  
* docs/ \- Architecture Decision Records and JSON Schema.  
* data/\<user-name\>/ \- Destination for JSONL banks (Gitignored).  
* reports/\<user-name\>/ \- Destination for generated markdown reports (Gitignored).