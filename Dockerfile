# ============================================================
# STAGE 1: Builder
# Kaam: Dependencies install karna
# Ye stage final image me NAHI aayegi — sirf build ke liye hai
# ============================================================
FROM python:3.11-slim AS builder

# WORKDIR — container ke andar working directory set karo
# Iske baad ke saare commands is folder me chalenge
# /app standard convention hai
WORKDIR /app

# requirements.txt PEHLE copy karo — code se pehle
# WHY? Docker layer caching ki wajah se
# Agar requirements.txt nahi badla toh pip install dobara nahi chalega
# Sirf code change hone pe sirf code layer rebuild hogi — fast builds!
COPY requirements.txt .

# Dependencies install karo
# --no-cache-dir: pip ka cache mat rakho — image size kam hogi
# --upgrade pip: latest pip use karo
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ============================================================
# STAGE 2: Runtime (Final Image)
# Kaam: Sirf app run karna
# Builder se sirf installed packages copy karenge
# Build tools, pip cache, etc. yahan NAHI aayenge
# ============================================================
FROM python:3.11-slim AS runtime

# Security best practice: root user mat use karo
# Agar container compromise ho jaaye toh attacker root nahi milega
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Builder stage se sirf installed Python packages copy karo
# /usr/local/lib/python3.11/site-packages me packages hote hain
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/gunicorn /usr/local/bin/gunicorn

# App ka code copy karo
COPY app/ .

# Files ka ownership appuser ko do
RUN chown -R appuser:appuser /app

# Non-root user pe switch karo
USER appuser

# EXPOSE — documentation ke liye hai
# Ye actually port open nahi karta — docker run -p karta hai
# Lekin ye batata hai ki app is port pe listen karta hai
EXPOSE 5000

# Health check — Docker khud container ki health monitor karega
# --interval=30s: har 30 second me check karo
# --timeout=10s: 10 second me response nahi aaya toh fail
# --start-period=5s: container start hone ke baad 5 sec wait karo
# --retries=3: 3 baar fail hone pe container "unhealthy" mark hoga
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# CMD — container start hone pe ye command chalegi
# Gunicorn: production-grade WSGI server
# -w 2: 2 worker processes (t2.micro ke liye 2 enough hai)
# -b 0.0.0.0:5000: sab interfaces pe port 5000 pe bind karo
# app:app — pehla 'app' module name (app.py), doosra 'app' Flask instance variable
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:5000", "--access-logfile", "-", "--error-logfile", "-", "app:app"]