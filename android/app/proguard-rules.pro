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

# jcifs-ng relies on BouncyCastle for several algorithms that Android's own
# JCE does not expose: MD4 (NTLM password hashing), AES-CMAC (SMB2 signing and
# SMB3 key derivation), etc. BouncyCastle registers algorithms by *reflection*
# using the original class names (Class.forName("...AES$Mappings")), so R8
# obfuscating or shrinking these classes makes the provider silently drop them.
# That surfaces as "CIFSUnsupportedCryptoException" / "no such algorithm:
# AESCMAC for provider BC" and makes SMB auth fail. Keep the whole provider.
-keep class org.bouncycastle.** { *; }
