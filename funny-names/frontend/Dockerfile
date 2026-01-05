FROM node:lts-alpine as build


WORKDIR /app

COPY package*.json .

#install packege 
# npm ci is faster
# npm ci installs EXACT versions from package-lock.json
# npm install may update packages, causing different results each build

# 👉 In Docker you want repeatable, predictable builds, so npm ci is safer.
RUN npm ci 

COPY . .


RUN npm run build 

FROM nginx:alpine


COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["/usr/sbin/nginx" ,"-g" ,"daemon ON;"]