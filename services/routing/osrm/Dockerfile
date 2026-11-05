# OSRM sidecar with the map graph baked in (built by osrm/prepare.sh or Cloud Build into osrm/data).
FROM ghcr.io/project-osrm/osrm-backend:v5.27.1

COPY data/map.osrm* /data/
EXPOSE 5000
# --max-table-size covers a 60-stop plan with room to spare (the API caps matrices at 2,500 points).
CMD ["osrm-routed", "--algorithm", "mld", "--port", "5000", "--max-table-size", "2500", "/data/map.osrm"]
