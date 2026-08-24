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

## Cleanup

Every spec files the ids it creates and deletes them afterwards, whatever the
outcome. A failed cleanup warns rather than failing the run, and each run
stamps its records with a nonce so leftovers from a previous failure never
collide with the current one.
