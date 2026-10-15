
FROM nginx:1.28-alpine

LABEL app="university-lms-portal"

COPY index.html /usr/share/nginx/html/index.html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
