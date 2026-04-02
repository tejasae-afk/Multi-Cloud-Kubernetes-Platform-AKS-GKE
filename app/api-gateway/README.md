# api-gateway

I kept this one thin on purpose. It fronts the order service, passes tracing headers through, and exposes the same health and metrics shape I use everywhere else. I stuck with the stdlib mux because five routes didn't need another dependency.
