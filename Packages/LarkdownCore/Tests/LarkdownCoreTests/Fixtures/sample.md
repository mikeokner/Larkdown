---
title: Larkdown Alpha Fixture
tags:
  - markdown
  - preview
---

# Larkdown Alpha Fixture

This fixture covers **common Markdown** that should remain stable for alpha
testing and regression checks.

## Tasks

- [x] Preserve local Markdown files
- [ ] Keep preview rendering responsive
- [ ] Support Finder as the normal open path

## Table

| Feature | Status |
| --- | --- |
| Front matter | Preserved |
| Tables | Rendered |
| Code fences | Highlighted |

> Preview behavior should be calm, readable, and predictable.

```python
def greet(name):
    return f"Hello, {name}"
```

Relative images should stay local:

![Diagram](images/diagram.png)

Visit <https://example.com> for an autolink example.
