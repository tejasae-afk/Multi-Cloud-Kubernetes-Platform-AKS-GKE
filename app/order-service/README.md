# order-service

This sits in the middle on purpose. It proves the mesh path from gateway to orders to inventory, and it gives me a fake write path I can hammer without touching a database yet. I wrote it in Go because that's still what I'd reach for first on a small HTTP service.
