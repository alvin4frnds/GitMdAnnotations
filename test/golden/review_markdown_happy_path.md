# Review — spec-auth
**Source:** 02-spec.md @ a3f91c
**Reviewed at:** 2026-04-20 09:32 local time

## Answers to open questions

### Q1: Should auth flow support magic links?
> Yes, but only as fallback after TOTP. See stroke group A at line 47.

### Q2: Session store: Redis or Postgres?
> Postgres. See stroke group B at line 102.

## Free-form notes

Auth section needs a diagram before revision.

## Spatial references

- Stroke group A → line 47
- Stroke group B → line 102
