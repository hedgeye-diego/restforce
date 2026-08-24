# Smoke specs

These run against a **real Salesforce org**. They create and delete records.

They are not part of `rake` or `rake spec`, and a bare `rspec` will skip every
one of them. Two separate things have to be true before any of them run:

1. `RESTFORCE_SMOKE=1` is set — `rake smoke` does this for you
2. credentials are in the environment

Without both, each example skips with a message saying which is missing. That
double guard is deliberate: credentials sitting in a shell should never be
enough on its own to make the test suite start writing to an org.

## Running them

```sh
SF_HOST=test.salesforce.com \
SF_USERNAME=... SF_PASSWORD=... SF_SECURITY_TOKEN=... \
SF_CLIENT_ID=... SF_CLIENT_SECRET=... \
bundle exec rake smoke
```

or with a token you already have:

```sh
SF_OAUTH_TOKEN=... SF_INSTANCE_URL=https://xxx.my.salesforce.com \
bundle exec rake smoke
```

One file at a time:

```sh
RESTFORCE_SMOKE=1 SF_... bundle exec rspec spec/smoke/url_encoding_spec.rb
```

**Use a sandbox.** `SF_HOST=test.salesforce.com`.

## Settings

| Variable | Default | Notes |
| --- | --- | --- |
| `RESTFORCE_SMOKE` | unset | must be `1` |
| `SF_API_VERSION` | `58.0` | graph specs skip below 50.0, collections below 42.0 |
| `SF_SOBJECT` | `Account` | the object most specs act on |
| `SF_HOST` | `login.salesforce.com` | use `test.salesforce.com` for a sandbox |

## What each file covers

| File | Covers |
| --- | --- |
| `url_encoding_spec.rb` | that an external id holding a space, slash or `@` round trips, and creates exactly one record |
| `composite_spec.rb` | subrequests, reference id resolution, query, and whether HEAD is accepted |
| `composite_graph_spec.rb` | per graph rollback, `composite_graph!`, reference ids inside a graph |
| `sobject_collections_spec.rb` | bulk create, retrieve, update, delete, and `null` for a missing id |
| `sobject_tree_spec.rb` | nested creation and all-or-nothing rollback |

`url_encoding_spec.rb` is the one that matters most. Restforce shipped a bug in
2018 where `CGI.escape` turned a space in an id into `+`, Salesforce did not
decode it, and upsert silently created duplicates (`705bf65`). It reached
production because the url looked correct in tests. Nothing checked at the
webmock level can rule that class of bug out — only these can.

## Org setup

Most specs need nothing. The upsert and external id ones need **one custom
field** on the object:

> Setup → Object Manager → Account → Fields & Relationships → New
> Type: Text, Length 100
> Tick both **External ID** and **Unique**

`smoke_helper.rb` finds it from the object's describe rather than expecting a
particular name, so any such field works. Specs that need one and cannot find
it skip with a message rather than failing.

## Idempotency and cleanup

Each **example** gets its own nonce, and every record it creates is named with
it. That is per example rather than per run on purpose: three specs assert a
record count by name, so a shared prefix would let a leak in one example fail a
different one, and the failure would point at the wrong place.

Cleanup runs whatever the outcome, in two passes:

1. **Tracked ids**, deleted newest first. Covers the normal case, and deleting
   a parent cascades to its children.
2. **A sweep** for anything still carrying this example's nonce. Covers the
   case that matters — an example asserting that *nothing* was created leaves
   records behind precisely when it fails, and has no ids to clean up with.

A record already gone is ignored quietly; anything else warns rather than
failing the run, so a cleanup problem never masks the result of the test.

Because names are scoped per example, a run that dies half way through cannot
affect the next one. Re-running is safe.

### What can still leave something behind

Three cases, none of which the hooks can reach:

- **The process is killed** — Ctrl-C, a crash, a dropped connection. RSpec's
  after hook never runs, so the in-flight example's records stay.
- **Cleanup itself fails** — no permission, a locked record, the org
  unreachable. It warns and moves on rather than failing the run.
- **Authentication expires mid-run**, so the sweep cannot query.

For any of those:

```sh
SF_OAUTH_TOKEN=... SF_INSTANCE_URL=... bundle exec rake smoke_clean
```

which deletes everything named `Restforce smoke`, `Restforce renamed` or
`Restforce updated` across Account, Contact and `SF_SOBJECT`, whatever nonce it
carried. Safe to run any time — it only matches names these specs create.

### Deleted, not purged

`destroy` is a Salesforce delete, so records go to the **Recycle Bin** rather
than disappearing. They leave SOQL results immediately and are purged
automatically, but they exist and count against storage until then. Empty the
bin from Setup if that matters to you.
