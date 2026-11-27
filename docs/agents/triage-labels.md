# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `triage`             | Maintainer needs to evaluate this issue  |
| `needs-info`               | `status:needs-info`  | Waiting on reporter for more information |
| `ready-for-agent`          | `status:ready`       | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `needs:blake`        | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

An issue carries one state role at a time. `status:needs-info` and `status:ready` are `status:*` labels, and an issue holds only one `status:*` label at once: remove the previous state label when you apply the next.

Edit the "Label in our tracker" column to match whatever vocabulary you actually use.

This repo also has an older `agent-ready` label (see `docs/agent-readiness/`). It is not part of this mapping: `status:ready` is the ready-for-agent label.
