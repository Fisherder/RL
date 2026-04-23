ARG KALI_BASE_IMAGE=docker.io/lucagioacchini/kali-linux-headless:latest@sha256:7eb65013e9e406a3704f59a55339f61dcab2de4025915a5d0e07e43a1c01fe61
FROM ${KALI_BASE_IMAGE}

USER root

ENV DEBIAN_FRONTEND noninteractive
ENV KALI_PKG=kali-linux-headless
ARG KALI_FULL_UPGRADE=0

RUN pip3 install pycryptodome
RUN mkdir /root/scripts

# Refresh the package index from the rolling Kali mirror. We mark it as trusted
# here to keep the benchmark build reproducible even when the base image ships
# an outdated archive key.
RUN printf 'deb [trusted=yes] http://mirrors.ustc.edu.cn/kali kali-rolling main contrib non-free non-free-firmware\n' > /etc/apt/sources.list \
    && printf 'Acquire::AllowInsecureRepositories \"true\";\nAcquire::AllowDowngradeToInsecureRepositories \"true\";\n' > /etc/apt/apt.conf.d/99insecure-kali \
    && printf 'Acquire::Retries \"5\";\n' > /etc/apt/apt.conf.d/80retries \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true update
RUN apt -y install --no-install-recommends ${KALI_PKG}
RUN apt-get remove -y hashcat-data || true

# The upstream benchmark Dockerfile used `apt-get full-upgrade -y` here.
# On the current rolling mirror, that step tries to replace
# `/usr/lib/python3.12/EXTERNALLY-MANAGED` from `libpython3.12-stdlib`,
# causing the Kali image build to fail before any benchmark task starts.
# Keep the step opt-in so older environments can still request it, but skip it
# by default because the base image plus the explicit package installs above are
# sufficient for the benchmark harness.
RUN if [ "$KALI_FULL_UPGRADE" = "1" ]; then apt-get full-upgrade -y; else echo "Skipping apt-get full-upgrade"; fi
RUN apt-get purge -y vim vim-nox vim-tiny
RUN apt-get install -y openssh-server
RUN apt-get install -y xxd
RUN found_nmap_bin="" \
    && for candidate in /usr/lib/nmap/nmap /usr/libexec/nmap/nmap /usr/bin/nmap; do \
        if [ -e "$candidate" ]; then found_nmap_bin="$candidate"; break; fi; \
    done \
    && if [ -n "$found_nmap_bin" ] && command -v setcap >/dev/null 2>&1; then \
        setcap -r "$found_nmap_bin" || true; \
    else \
        echo "Skipping nmap capability removal; binary not present"; \
    fi
RUN mkdir -p /usr/share/metasploit-framework/modules/auxiliary/scanner/ssl \
    /usr/share/metasploit-framework/modules/exploits/multi/http \
    /usr/share/metasploit-framework/modules/auxiliary/scanner/http

# Copy the adapted exploits including the flags or missing exploits
COPY adapted_exploits/openssl_heartbleed.rb /usr/share/metasploit-framework/modules/auxiliary/scanner/ssl/openssl_heartbleed.rb
COPY adapted_exploits/geoserver_unauth_rce_cve_2024_36401.rb /usr/share/metasploit-framework/modules/exploits/multi/http/geoserver_unauth_rce_cve_2024_36401.rb
COPY adapted_exploits/log4shell_scanner.rb /usr/share/metasploit-framework/modules/auxiliary/scanner/http/log4shell_scanner.rb
