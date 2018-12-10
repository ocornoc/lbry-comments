# Comment System for the LBRY Network

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

***Please make sure to change the file `seed`.***

## Busted support

If you have busted installed, you can run busted from the project directory in order to run the tests.

## Dependencies

* [libsodium](https://github.com/jedisct1/libsodium)
* [OpenResty](https://openresty.org/en/)
* [luajit](http://luajit.org/luajit.html) >= 2.0.0 (included in OpenResty)
* [lua-cjson](https://github.com/mpx/lua-cjson) (included in OpenResty)
* [luasocket](https://github.com/diegonehab/luasocket)
* [LuaFileSystem](https://keplerproject.github.io/luafilesystem/)
* [LuaSQL](https://keplerproject.github.io/luasql/) (using SQLite3)
* [busted](https://olivinelabs.com/busted/) (only for debug)

## Things to come

### For the backend:

(In order of likelihood of earliest completion)

- [x] busted support
- [x] comment u/d-voting
- [ ] claim/comment deletion
- [ ] LDoc/LuaDoc-style documentation
- [ ] comment editing
- [ ] posting backups to LBRY
