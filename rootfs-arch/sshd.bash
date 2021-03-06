#!/bin/bash

$schroot systemctl reenable sshd.service

$sudo patch -d $rootfsdir -p1 -N -r - <<'EOF'
diff -Naur a/etc/ssh/sshd_config  b/etc/ssh/sshd_config 
--- a/etc/ssh/sshd_config	2018-02-06 14:57:10.000000000 +0100
+++ b/etc/ssh/sshd_config	2018-01-16 22:21:16.000000000 +0100
@@ -34 +34 @@
-#PermitRootLogin prohibit-password
+PermitRootLogin yes
EOF

