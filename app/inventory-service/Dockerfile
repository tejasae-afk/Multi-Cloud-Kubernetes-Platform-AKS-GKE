FROM python:3.12.13-slim-bookworm AS build
ENV VENV=/opt/venv
ENV PATH="${VENV}/bin:${PATH}"
WORKDIR /app

RUN python -m venv ${VENV}
COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip && pip install --no-cache-dir -r requirements.txt

FROM python:3.12.13-slim-bookworm AS runtime
ENV PATH="/opt/venv/bin:${PATH}"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8082
WORKDIR /app

RUN groupadd --system app && useradd --system --gid app --create-home --home-dir /home/app app
COPY --from=build /opt/venv /opt/venv
COPY . /app

USER app
EXPOSE 8082
CMD ["gunicorn", "-c", "gunicorn.conf.py", "app:app"]
