bind = '0.0.0.0:8082'
workers = 1
threads = 8
timeout = 30
graceful_timeout = 20
accesslog = '-'
errorlog = '-'

# I keep this at one worker so Prometheus metrics stay sane without multiprocess glue.
# good enough for now
