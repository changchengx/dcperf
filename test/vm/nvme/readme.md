- Single PF test case
```shell
base -x single_pf_lu.sh
```

- Single PF(admin only) and 2 VFs
```shell
base -x pf_2vf_lu_src.sh
base -x pf_2vf_lu_dst.sh
```

- one hotplug function
For the first time, it needs to create hot plug function successfully.
```shell
base -x hotplug_1pf_lu.sh start
```
After the first time with creating the hot plug function successfully,
do not add any parameter when running the script.
