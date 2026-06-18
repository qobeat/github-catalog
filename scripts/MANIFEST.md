# AI Agent Scripts Manifest: Execution Guide

**ATTENTION LLM / AGENT:** This document dictates how to execute the `github-catalog` pipeline to discover, fetch, and report on git repositories.

## The Standard Execution Pipeline

To generate a catalog and report, you must run the scripts in the following sequence. Do not call `github-catalog-datafetcher.sh` directly unless debugging a single repository.

### Step 1: Define the Target List
Create a plain text file (e.g., `repos.txt`) containing the repositories to scan.
Format: `slug` [optional: `url` `branch`]
```text
my-unix-scripts
ados-framework    git@github.com:owner/ados-framework.git   main