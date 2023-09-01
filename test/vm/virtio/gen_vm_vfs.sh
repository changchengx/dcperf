#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright(c) 2023 Liu, Changcheng <changcheng.liu@aliyun.com>

group_number=$1

tbdfs[0]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x4'/>"
tbdfs[1]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x5'/>"
tbdfs[2]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x6'/>"
tbdfs[3]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x7'/>"
tbdfs[4]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>"
tbdfs[5]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x1'/>"
tbdfs[6]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x2'/>"
tbdfs[7]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x3'/>"
tbdfs[8]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x4'/>"
tbdfs[9]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x5'/>"
tbdfs[10]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x6'/>"
tbdfs[11]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x7'/>"
tbdfs[12]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>"
tbdfs[13]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x1'/>"
tbdfs[14]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x2'/>"
tbdfs[15]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x3'/>"
tbdfs[16]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x4'/>"
tbdfs[17]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x5'/>"
tbdfs[18]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x6'/>"
tbdfs[19]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x7'/>"
tbdfs[20]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>"
tbdfs[21]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x1'/>"
tbdfs[22]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x2'/>"
tbdfs[23]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x3'/>"
tbdfs[24]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x4'/>"
tbdfs[25]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x5'/>"
tbdfs[26]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x6'/>"
tbdfs[27]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x7'/>"
tbdfs[28]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>"
tbdfs[29]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x1'/>"
tbdfs[30]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x2'/>"
tbdfs[31]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x3'/>"
tbdfs[32]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x4'/>"
tbdfs[33]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x5'/>"
tbdfs[34]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x6'/>"
tbdfs[35]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x7'/>"
tbdfs[36]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x0'/>"
tbdfs[37]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x1'/>"
tbdfs[38]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x2'/>"
tbdfs[39]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x3'/>"
tbdfs[40]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x4'/>"
tbdfs[41]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x5'/>"
tbdfs[42]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x6'/>"
tbdfs[43]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x7'/>"
tbdfs[44]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x0'/>"
tbdfs[45]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x1'/>"
tbdfs[46]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x2'/>"
tbdfs[47]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x3'/>"
tbdfs[48]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x4'/>"
tbdfs[49]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x5'/>"
tbdfs[50]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x6'/>"
tbdfs[51]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x7'/>"
tbdfs[52]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0b' function='0x0'/>"
tbdfs[53]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0b' function='0x1'/>"
tbdfs[54]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0b' function='0x2'/>"
tbdfs[55]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0b' function='0x3'/>"
tbdfs[56]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0b' function='0x4'/>"
tbdfs[57]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0b' function='0x5'/>"
tbdfs[58]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0b' function='0x6'/>"
tbdfs[59]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0b' function='0x7'/>"
tbdfs[60]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x0'/>"
tbdfs[61]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x1'/>"
tbdfs[62]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x2'/>"
tbdfs[63]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x3'/>"
tbdfs[64]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x4'/>"
tbdfs[65]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x5'/>"
tbdfs[66]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x6'/>"
tbdfs[67]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0c' function='0x7'/>"
tbdfs[68]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0d' function='0x0'/>"
tbdfs[69]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0d' function='0x1'/>"
tbdfs[70]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0d' function='0x2'/>"
tbdfs[71]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0d' function='0x3'/>"
tbdfs[72]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0d' function='0x4'/>"
tbdfs[73]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0d' function='0x5'/>"
tbdfs[74]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0d' function='0x6'/>"
tbdfs[75]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0d' function='0x7'/>"
tbdfs[76]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0e' function='0x0'/>"
tbdfs[77]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0e' function='0x1'/>"
tbdfs[78]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0e' function='0x2'/>"
tbdfs[79]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0e' function='0x3'/>"
tbdfs[80]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0e' function='0x4'/>"
tbdfs[81]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0e' function='0x5'/>"
tbdfs[82]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0e' function='0x6'/>"
tbdfs[83]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0e' function='0x7'/>"
tbdfs[84]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0f' function='0x0'/>"
tbdfs[85]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0f' function='0x1'/>"
tbdfs[86]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0f' function='0x2'/>"
tbdfs[87]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0f' function='0x3'/>"
tbdfs[88]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0f' function='0x4'/>"
tbdfs[89]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0f' function='0x5'/>"
tbdfs[90]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0f' function='0x6'/>"
tbdfs[91]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x0f' function='0x7'/>"
tbdfs[92]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x0'/>"
tbdfs[93]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x1'/>"
tbdfs[94]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x2'/>"
tbdfs[95]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x3'/>"
tbdfs[96]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x4'/>"
tbdfs[97]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x5'/>"
tbdfs[98]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x6'/>"
tbdfs[99]="    <address type='pci' domain='0x0000' bus='0x00' slot='0x10' function='0x7'/>"

lines=$(wc -l x | cut -d ' ' -f 1)

array_number=$((lines / group_number))
temp=$((array_number * group_number))
tail_array_number=$((lines - temp))

declare -a array

for i in `seq 0 $((array_number - 1))`
do
    first_line=$((i * group_number + 1))
    last_line=$((first_line + group_number - 1))
    array[$i]=`sed -n -e "$first_line,${last_line}p" x`
done

gg () {
    mkdir -p $2
    bdfs=`echo $1`
    bdfs=($bdfs)
    for ((idx=0; idx<${#bdfs[@]}; idx++))
    do
       bdf=${bdfs[$idx]}
       bus="0x"`echo $bdf | cut -d ':' -f 1`
       dev="0x"`echo $bdf | cut -d ':' -f 2 | cut -d '.' -f 1`
       func="0x"`echo $bdf | cut -d ':' -f 2 | cut -d '.' -f 2`
       tbdf=${tbdfs[$idx]}

sudo cat > $2/vf$idx.xml <<EOT
<hostdev mode='subsystem' type='pci' managed='yes'>
  <driver name='vfio'/>
  <source>
    <address domain='0x0000' bus='$bus' slot='$dev' function='$func'/>
  </source>
$tbdf
</hostdev>
EOT

    done
}


for i in `seq 0 $((array_number - 1))`
do
gg "${array[$i]}" $i
done
