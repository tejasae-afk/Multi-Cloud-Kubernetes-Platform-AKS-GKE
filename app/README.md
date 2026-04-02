# app

I split the app into three tiny services so I could prove cross-cloud routing with real traffic instead of a hello-world page. The gateway fronts orders, orders calls inventory, and inventory stays in Flask on purpose because mixed stacks are normal. I smoke test all of it locally with docker compose before I push images and install the Helm chart.
