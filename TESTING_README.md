# Expense MCP End-to-End Testing Prompts

Use this file to test the full project flow in Claude with your remote MCP server.

## Prerequisites

- MCP server is running and reachable.
- Claude Desktop is configured with your server URL.
- `X-API-Key` header is set in Claude config for each user profile you test.
- Database migrations are already applied.

---

## A. Individual (Personal) Flow E2E

Use these prompts in order with one user account.

### 1) Identity check

```text
Run whoami and confirm my user id.
```

Expected:
- Returns `status: success`
- Returns your `user_id`

### 2) Add personal expenses

```text
Add an expense:
- Date: 2026-05-01
- Amount: 450
- Category: Food & Dining
- Subcategory: Lunch
- Note: Office lunch
```

```text
Add an expense:
- Date: 2026-05-02
- Amount: 1200
- Category: Transportation
- Subcategory: Taxi/Ola/Uber
- Note: Airport drop
```

Expected:
- Both insert successfully
- Each returns a transaction id/message

### 3) List expenses

```text
List my expenses from 2026-05-01 to 2026-05-31.
```

Expected:
- Both expenses appear
- Date range filtering works

### 4) Summarize expenses

```text
Summarize my spending from 2026-05-01 to 2026-05-31 by category.
```

Expected:
- Category totals are correct
- Count per category is correct

### 5) Optional category-specific summary

```text
Summarize my spending from 2026-05-01 to 2026-05-31 only for category Food & Dining.
```

Expected:
- Only Food & Dining totals are returned

---

## B. Group Flow E2E (Two Users)

This test needs two users:
- **User A** (group creator)
- **User B** (member who approves)

Run User A steps in A's Claude profile, and User B steps in B's profile.

### 1) User A creates group

```text
Create a group named "Goa Trip Test" with kind "trip".
Then list my groups.
```

Expected:
- Group created with `group_id`
- Group appears in User A's groups

### 2) User A creates invite

```text
Create an invite for my group "<GROUP_ID>" valid for 7 days.
```

Expected:
- Returns an `invite_code`

### 3) User B redeems invite

```text
Redeem this invite code: <INVITE_CODE>
Then list my groups.
```

Expected:
- User B joins same group
- Group appears in User B's groups

### 4) User A adds group expense

```text
Add a group expense:
- Group ID: <GROUP_ID>
- Date: 2026-05-03
- Amount: 2000
- Category: Food & Dining
- Subcategory: Dinner
- Note: Beach dinner
```

Expected:
- Transaction is created (usually `pending`)
- Returns `transaction_id`

### 5) User B checks pending approvals

```text
Show my pending approvals.
```

Expected:
- Shows the pending transaction created by User A

### 6) User B approves the expense

```text
Approve group expense transaction id: <TRANSACTION_ID>
```

Expected:
- Vote accepted
- Transaction moves to `approved` (when all required members approved)

### 7) Validate group transactions

Prompt from either user:

```text
List group transactions for group id <GROUP_ID> from 2026-05-01 to 2026-05-31.
```

Expected:
- Approved transaction visible to group members

### 8) Check balances

```text
Show group balances for <GROUP_ID>.
Then simplify debts for <GROUP_ID>.
```

Expected:
- `group_balances` returns net balances
- `simplify_group_debts` suggests transfers

### 9) Record settlement

```text
Record settlement:
- Group ID: <GROUP_ID>
- From User ID: <DEBTOR_USER_ID>
- To User ID: <CREDITOR_USER_ID>
- Amount: 500
- Date: 2026-05-04
- Note: Partial settlement via UPI
```

Expected:
- Settlement recorded successfully
- New settlement id returned

### 10) Re-check balances after settlement

```text
Show group balances for <GROUP_ID> including settlements.
List group settlements for <GROUP_ID>.
```

Expected:
- Balances adjust after settlement
- Settlement appears in history

---

## C. Rejection Path Test (Optional)

Use this to validate rejection workflow.

### 1) User A creates another pending group expense

```text
Add a group expense in <GROUP_ID>:
- Date: 2026-05-05
- Amount: 900
- Category: Entertainment
- Subcategory: Movies
- Note: Late night movie
```

### 2) User B rejects it

```text
Reject group expense transaction id: <TRANSACTION_ID>
```

Expected:
- Transaction becomes `rejected`
- It should not affect approved-balance calculations

---

## D. Fast Regression Prompt Pack

If you want one quick run, use this mini pack:

1. `Run whoami.`
2. `Add an expense of 100 for tea today under Food & Dining.`
3. `List my expenses for this month.`
4. `Create a group named "Regression Group".`
5. `Create an invite for that group.`
6. (Second user) `Redeem invite code ...`
7. `Add group expense 600 for dinner.`
8. (Second user) `Show pending approvals and approve the expense.`
9. `Show group balances and simplify debts.`
10. `Record settlement of 200 and show balances again.`

---

## E. Common Failures and What They Mean

- `Invalid or expired API key`  
  Re-run `login_get_api_key`, update Claude header, restart Claude.

- `JWT missing sub claim`  
  Wrong token path or refresh-token/API-key mismatch. Check auth migrations and API-key refresh flow.

- `infinite recursion detected in policy`  
  RLS policy recursion issue in DB. Fix policy/function and re-test.

- `not a member of this group`  
  Invite not redeemed, wrong `group_id`, or wrong user profile.

---

## F. Suggested Test Data Conventions

- Keep one test group name per run, e.g. `Goa Trip Test YYYY-MM-DD`.
- Use fixed dates for deterministic validation.
- Keep notes explicit (`Office lunch`, `Beach dinner`) to quickly spot records.

