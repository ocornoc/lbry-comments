# Comment System for the LBRY Network

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

***Please make sure to change the file `seed`.***

## Permissions

Make sure to allow the user `nobody` to access the project's root directory. This can be done as so:

`sudo chown -R nobody . `

## How to use

You must use the file `start` as it supplies the server with some necessary global variables.

Run `./start -h` for more details.

## Dependencies

* [libsodium](https://github.com/jedisct1/libsodium)
* [OpenResty](https://openresty.org/en/)
* [LuaSQL](https://keplerproject.github.io/luasql/) (using SQLite3)
* [busted](https://olivinelabs.com/busted/) (only for debug)
* [LuaCov](https://keplerproject.github.io/luacov/) (only for *extra* debug)
* [LDoc](https://github.com/stevedonovan/LDoc) (only for documentation gen)

## Things to come

These will come near the end of the project:

- [ ] posting backups to LBRY

These are planned to be completed at an indeterminate time, due to factors outside of our control:

- [ ] claim/comment deletion
- [ ] comment editing
