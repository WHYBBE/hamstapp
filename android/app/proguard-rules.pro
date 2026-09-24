# Remote APK sources (FTP via commons-net, SMB via jcifs-ng).
# jcifs-ng references optional JSE-only APIs that Android lacks (Kerberos,
# Naming/LDAP, Servlet, AWT). None are used for SMB/guest/NTLM access, so
# silence R8 for them instead of shipping the classes.
-dontwarn org.slf4j.**
-dontwarn org.apache.**
-dontwarn javax.**
-dontwarn org.ietf.**
-dontwarn java.awt.**
-dontwarn com.sun.**
-dontwarn org.bouncycastle.**
-keep class jcifs.** { *; }
-keep class org.apache.commons.net.** { *; }
