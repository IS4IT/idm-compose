# IDM Development environment composed with Docker

Build and manage disposable NetIQ Identity Manager environments for development, testing and learning about IDM containers on Docker.

## Requirements

- `docker` and `docker compose` (also works with Docker Desktop)
- `bash`, `openssl`, `sed`, `find`, `grep`, `envsubst`, `tr`, `keytool`
- docker images specified in `compose.yaml_template` locally available or pullable
- `ca.crt` imported as a trusted root CA certificate into your browser
- the follwing entries added to `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts`) on your docker host:
```
 127.0.0.1	apps.idm.local
 127.0.0.1	db.idm.local
 127.0.0.1	forms.idm.local
 127.0.0.1	idcon.idm.local
 127.0.0.1	idv.idm.local
 127.0.0.1	iman.idm.local
 127.0.0.1	mq.idm.local
 127.0.0.1	osp.idm.local
 127.0.0.1	sspr.idm.local
 ```
- If you run docker inside a virtual machine (rather than in Docker Desktop or Colima) and want to access IDM from the VM host machine, also add the above hostnames to `/etc/hosts` on the VM host, replacing "127.0.0.1" with the VM's IP address.

Tested on 
 - macOS (Intel and Apple Silicon) with 
   - [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   - [Colima](https://github.com/abiosoft/colima)
   - [Rancher Desktop](https://rancherdesktop.io/)
 - Ubuntu 24.04
   - on hardware or in a virtual machine
   - must be able to run x86_64 container (natively or through multi-arch support + Rosetta, UTM, QEMU...)
   - distribution-provided docker packages:
     - docker-ce
     - docker-ce-cli
     - docker-buildx-plugin
     - docker-compose-plugin
     - java-common

## Quickstart

- clone or copy this folder and run `./idm-compose init`
- set `SUBNET`, `PORT_BASE` and/or `TREENAME` to override the default values
- add `-p <project name>` to set a custom compose project name (defaults to the name of the project folder)
- all command line options are passed through to `docker compose`
- all commands other than `ìnit` and their options are passed through to `docker compose`
- add files/folders to `config` subfolder for further customization, e.g.
  - add .jar/.so files to the `config/idm/mountfiles` and `config/idm/mountfiles` subfolders to install new or updated
  - add .ldif/.sch files to `config/idm/mountfiles` to extend schema and/or prepopulate Edirectory

## Key concepts

Running NetIQ Identity Manager as a containerized service is described briefly in the [product documentation](https://www.netiq.com/documentation/identity-manager-49/setup_linux/data/t44hxf3fe2mn.html) and is targeted towards production environments. 

This tool on the other hands is primarily about easily creating IDM environments for development, testing and learning. `idm-compose` utilizes `docker build` and `docker compose` to work around the quirks and issues that come with the original docker images and initialize new environments quickly and without much manual configuration

#### Stacks (in development)

`idm-compose` allows to create up to 63 stacks in parallel, numbered 1..63. Each stack has it's name, subnet and published port range derived from it's id. For example stack 27 will be named "idm27" live on subnet x.y.27.0/24 and publish applications on ports 127.0.0.1:27xxx

If you want to run just a single stack, no stack id needs to be provided.

#### Networking

Unlike the single server setup described in the documentation, which uses `host`networking, `idm-compose` sets up `bridge` networking and only selected ports are mapped to the `localhost` interface. This allows for multiple isolated environments to co-exist and does not expose them to the outside world.

Networking can be configured in `compose.yaml_template` to bind to the default `0.0.0.0` instead of just `localhost`, which is required if docker runs inside a virtual machine and IDM shall be accessible from the host machine. In that case the `*.idm.local` entries in `/etc/hosts` need to point to the VM's IP address instead of `127.0.0.1`

Instead of using networking parameters derived from the stack id you can override them by setting the `SUBNET` and `PORT_BASE` environment variables prior to calling `idm-compose`, to avoid conflicts with other software.

#### PKI & Certificates

The Identity Applications rely heavily on verified and trusted TLS connections, which can be a major hassle and hinder quickly setting up isolated, disposable dev/test environments. `idm-compose` works around this by creating it's own local CA and wildcard server certificate for all exposed web services. The same CA is used for all stacks so it's public key needs to be imported into your browser only once.

Instead of using a local CA you can provide your own `ca.key` and `ca.crt`files (PEM format) and those will be used to sign the server certificate.

You can also provide an already signed wildcard server certificate and private key (`server.key`, `server.crt` and `ca.crt`), eliminating the need for a local CA in the first place. Make sure to also provide `ca.crt` in that case.

#### Customized Images

The official IDM docker images provided by OpenText are used as base images to build enhanced and/or bug fixed images on top of them. A Dockerfile for each image can be found under the `images` subfolder.

#### Command pass-through

`idm-compose` handles only the `ìnit` command by itself, all other commands are passed through to `docker compose`. 

See `idm-compose --help` for more details.

## Troubleshooting

Some containers support debugging, set the appropriate env variable in compose.yaml and restart the container.

While `idm-compose` is working you may want to follow its progress in more detail by running the following commands in separate terminals once the idv container is running:

```
./idm-compose logs -f
```
```
./idm-compose exec idv tail -qFn0 /config/idm/log/idmconfigure.log /config/osp/log/idmconfigure.log /config/userapp/log/idmconfigure.log
```
```
./idm-compose exec idv tail -qFn0 /config/userapp/tomcat/logs/catalina.out /config/osp/tomcat/logs/catalina.out
```

In order to pull images form hub.is4it.de, you may need to login first with `docker login hub.is4it.de`

Pulling images concurrently does not work well with hub.is4it.de, to prevent this configure your docker deamon with:
```
{
    "max-concurrent-uploads": 1,
    "max-concurrent-downloads": 1
}
```

## Known issues

#### idv:
- Occationally the schema does not get extended properly, which causes the apps container to fail installing the US and RRSD drivers.
- Sometimes IDM cannot be configured and fails with "Could not find prompt ID" even though the listed prompt is set in /config/silent.properties

#### apps:
- IDMProv.war cannot be deployed completely, catalina.out shows: ```org.apache.catalina.startup.HostConfig.deployWAR Error deploying web application archive [/opt/netiq/idm/apps/tomcat/webapps/IDMProv.war]```
  - Workaround: delete IDMProv folder and restart the container

#### sspr:
- Server certificate is not imported automatically
  - Workaround: unlock the configuration by editing /config/SSPRConfiguration.xml or running `/app/command.sh ConfigUnlock` inside the container
  - Open https://sspr.idm.local:2445/sspr/private/config/editor and import keys.pfx (PKCS12, Alias "tomcat")
  - Lock configuration
  - restart container
- SPPR shown blank page after login attempt due to OAuth/PKI error: `5057 ERROR_SERVICE_UNREACHABLE (error while making http request: no root CA certificates in configuration trust store`

## To Do

- complete STACK support
- fix SSPR container certificates
- add reporting and fanout containers

## Performance

It takes about 20 minutes to complete initializing a complete environment on an M3 MacBook Pro with Docker Desktop (using Virtualization Framework + Rosetta). A pure IDM engine environment (idv, rl, idcon, iman) without Identity Apps is ready in about 5 minutes.

## Example

```
$ ./idm-compose init
Creating compose.yaml from template...
Creating config/silent.properties from template...
Creating config/data/SSPRConfiguration.xml from template...
Creating config/data/edirapi.conf from template...
Installing services: apps db forms idcon idv iman osp rl sspr
Using existing keystore ./config/data/keys.pfx
Your keystore contains 2 entries
idm-local_ca, 23 Jan 2025, trustedCertEntry,
tomcat, 23 Jan 2025, PrivateKeyEntry,
 Not Before: Jan 13 13:42:58 2025 GMT
 Not After : Jan 11 13:42:58 2035 GMT
 Subject: CN=*.idm.local
 DNS:*.idm.local, IP Address:127.0.0.1
Importing keystore config/data/keys.pfx to config/data/.p12...
Warning: Overwriting existing alias tomcat in destination keystore
Entry for alias tomcat successfully imported.
Warning: Overwriting existing alias idm-local_ca in destination keystore
Entry for alias idm-local_ca successfully imported.
Import command completed:  2 entries successfully imported, 0 entries failed or cancelled
Zertifikat in Datei <ca.der> gespeichert
Zertifikat in Datei <server.der> gespeichert
[+] Creating 15/14
 ✔ Network idm-compose_default    Created
 ✔ Volume "idm-compose_config"    Created
 ✔ Volume "idm-compose_trace"     Created
 ✔ Volume "idm-compose_cache"     Created
 ✔ Volume "idm-compose_sspr"      Created
 ✔ Volume "idm-compose_db"        Created
 ✔ Container idm-compose-iman-1   Created
 ✔ Container idm-compose-idcon-1  Created
 ✔ Container idm-compose-db-1     Created
 ✔ Container idm-compose-rl-1     Created
 ✔ Container idm-compose-idv-1    Created
 ✔ Container idm-compose-osp-1    Created
 ✔ Container idm-compose-apps-1   Created
 ✔ Container idm-compose-sspr-1   Created
 ✔ Container idm-compose-forms-1  Created
[+] Copying 1/1
 ✔ idm-compose-idv-1 copy ./config to idm-compose-idv-1:/ Copied
[+] Copying 1/0
 ✔ idm-compose-db-1 copy ./config/data/init.sql to idm-compose-db-1:/docker-entrypoint-initdb.d/ Copied
[+] Restarting 4/4
 ✔ Container idm-compose-idv-1   Started
 ✔ Container idm-compose-iman-1  Started
 ✔ Container idm-compose-db-1    Started
 ✔ Container idm-compose-rl-1    Started
[+] Copying 1/0
 ✔ idm-compose-iman-1 copy ./config/data/.p12 to idm-compose-iman-1:/var/opt/novell/novlwww/ Copied
Waiting for Edirectory to initialize.................................................. Done
Importing /config/idm/mountfiles/aieExtensions.ldif
Importing /config/idm/mountfiles/data.ldif
[+] Copying 1/0
 ✔ idm-compose-idv-1 copy idm-compose-idv-1:/config/idm/eDirectory_data/data/SSCert.pem to . Copied
Adding symlink  '/config/data/SSCert.pem' -> '/config/idm/eDirectory_data/data/SSCert.pem'
[+] Restarting 1/1
 ✔ Container idm-compose-idcon-1  Started
[+] Restarting 1/1
 ✔ Container idm-compose-osp-1  Started
Waiting for OSP to initialize............ Done
Importing tree CA into OSP keystores
Certificate was added to keystore
Importing keystore /config/osp/tomcat/conf/tomcat.ks to /config/osp/tomcat/conf/idm.jks...
Entry for alias tomcat successfully imported.
Warning: Overwriting existing alias idm-local_ca in destination keystore
Entry for alias idm-local_ca successfully imported.
Entry for alias idm-compose_ca successfully imported.
Import command completed:  3 entries successfully imported, 0 entries failed or cancelled
[+] Restarting 1/1
 ✔ Container idm-compose-osp-1  Started
Waiting for OSP to restart........... Done
[+] Restarting 1/1
 ✔ Container idm-compose-apps-1  Started
Waiting for User App to initialize..............................
Importing keystore /config/userapp/tomcat/conf/tomcat.ks to /config/userapp/tomcat/conf/idm.jks...
Entry for alias tomcat successfully imported.
Warning: Overwriting existing alias idm-local_ca in destination keystore
Entry for alias idm-local_ca successfully imported.
Import command completed:  2 entries successfully imported, 0 entries failed or cancelled
............................... Done
[+] Restarting 1/1
 ✔ Container idm-compose-apps-1  Started
[+] Copying 1/0 App (this may take a few minutes to complete)
 ✔ idm-compose-forms-1 copy ./config/FormRenderer/nginx/cert to idm-compose-forms-1:/config/FormRenderer/nginx/ Copied
[+] Restarting 1/1
 ✔ Container idm-compose-forms-1  Started
[+] Copying 1/0
 ✔ idm-compose-sspr-1 copy ./config/data/ to idm-compose-sspr-1:/config/ Copied
[+] Copying 1/0
 ✔ idm-compose-sspr-1 copy ./config/silent.properties to idm-compose-sspr-1:/config/ Copied
[+] Running 1/1
 ✔ Container idm-compose-sspr-1  Started
Waiting for SSPR to initialize........ Done
[+] Copying 1/0
 ✔ idm-compose-sspr-1 copy config/data/SSPRConfiguration.xml to idm-compose-sspr-1:/config/ Copied

The following services should now be available for login as 'cn=admin,ou=sa,o=system' with password 'n0v3ll':

 LDAP       ->	ldap://idv.idm.local:1389
            ->	ldaps://idv.idm.local:1636
 iMonitor   ->	https://idv.idm.local:1830/nds
 iManager   ->	https://iman.idm.local:1843/nps
 ID Console ->	https://idcon.idm.local:1900/identityconsole

Use 'cn=appadmin,ou=sa,o=data' with password 'n0v3ll' to log in to:

 UserApp    ->	https://apps.idm.local:1443/idmdash
 SSPR       ->	https://sspr.idm.local:1445/sspr

Make sure to import <path to idm-compose></path>/ca.crt as a trusted root CA certificate into your browser and
add the following lines to `/etc/hosts` on your Docker host:

 127.0.0.1	apps.idm.local
 127.0.0.1	db.idm.local
 127.0.0.1	forms.idm.local
 127.0.0.1	idcon.idm.local
 127.0.0.1	idv.idm.local
 127.0.0.1	iman.idm.local
 127.0.0.1	mq.idm.local
 127.0.0.1	osp.idm.local
 127.0.0.1	sspr.idm.local

Designer requires a NAT mapping from the internal address 172.77.0.2:636 to 127.0.0.1:1636 to properly connect to the new tree.

The Edirectory CA certificate for the IDM-COMPOSE tree can be found at <path to idm-compose>/SSCert.pem to validate LDAP and iMonitor connections.

```
