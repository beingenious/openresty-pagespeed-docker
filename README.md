# openresty with pagespeed

openresty-nginx-pagespeed

## how to build

* basic

```code
docker build -t dalongrong/openresty-pagespeed:1.13.35.2 .
```

* with pagespeed

```code
docker build -t dalongrong/openresty-pagespeed:1.13.35.2-fat -f Dockerfile.fat .

```