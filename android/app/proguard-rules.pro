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

# jcifs-ng needs MD4 to compute NTLM responses, and MD4 is only available from
# the bundled BouncyCastle provider. BouncyCastle registers algorithms by
# *reflection* using the original class names (Class.forName("...MD4$Mappings")
# etc). R8 obfuscating or shrinking those classes makes the provider silently
# drop MD4, which surfaces as "CIFSUnsupportedCryptoException" and SMB auth
# failing. Keep the provider and the digest implementations with their names.
-keep class org.bouncycastle.jce.provider.BouncyCastleProvider { *; }
-keep class org.bouncycastle.jcajce.provider.digest.** { *; }
-keep class org.bouncycastle.jcajce.provider.symmetric.util.ClassUtil { *; }
-keep class org.bouncycastle.crypto.digests.** { *; }
-keep class org.bouncycastle.crypto.CryptoServiceProperties { *; }
