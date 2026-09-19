# NetSuite connector

The Acme NetSuite connector reads records from NetSuite and writes them to your destination.

## Synchronization direction

The NetSuite integration is one-way only. Acme reads from NetSuite and writes to your warehouse or downstream system. Writing changes back into NetSuite is not supported, so the NetSuite connector does not support bidirectional synchronization.

Teams that need changes written back to NetSuite typically pair Acme with a workflow tool that owns the write path.

## Supported record types

Customers, Vendors, Invoices, Sales Orders, Purchase Orders, Items and Journal Entries. Custom records are supported when they expose a SuiteTalk endpoint.

## Sync frequency

The NetSuite connector syncs hourly on the Business plan and on a custom schedule on the Enterprise plan. The minimum interval is five minutes.

## Credential expiry

If the NetSuite credential expires mid-sync, the run is marked failed and no partial data is written to the destination. Acme raises an alert and retries the run once the credential is renewed.
