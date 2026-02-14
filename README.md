# roblox-water

```
$ ls ~/Documents/Roblox/Plugins
RojoManagedPlugin.rbxm

$ ps aux | rg '[R]obloxStudio' | awk '{print $2}'
77106
77108

$ ps aux | rg '[r]ojo serve' | awk '{print $2}'
77104

$ ./scripts/rbxcloud.py place get
{
  "path": "universes/9724315460/places/120521808331460",
  "createTime": "2026-02-14T14:24:54.873Z",
  "updateTime": "2026-02-14T14:32:52.324318700Z",
  "displayName": "roblox-water",
  "description": "",
  "serverSize": 50
}
```
