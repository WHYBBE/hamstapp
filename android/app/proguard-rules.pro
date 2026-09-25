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
# commons-net ships many protocols (SMTP/POP3/IMAP/Telnet/...). We only use FTP,
# but the FTP parser factory loads parser classes by name, so keep the FTP
# package (names included) and let R8 drop the rest.
-keep class org.apache.commons.net.ftp.** { *; }

# jcifs-ng relies on BouncyCastle for algorithms Android's own JCE lacks:
# MD4 (NTLM password hashing) and AES-CMAC (SMB2 signing / SMB3 key derivation).
# BouncyCastle registers algorithms by *reflection* using the original class
# names (Class.forName("...MD4$Mappings"), addAlgorithm("AESCMAC",
# "...AES$AESCMAC")), so R8 must not rename or drop the provider glue.
#
# Keep the provider and the digest/symmetric provider packages (names included)
# so those reflective lookups still resolve, but let R8 shrink everything else
# in BouncyCastle (PQC, TLS, X.509, asymmetric, ...) that jcifs never uses.
# The underlying crypto.* implementation classes are referenced directly by the
# kept provider classes, so they are retained automatically.
-keep class org.bouncycastle.jce.provider.BouncyCastleProvider { *; }
-keep class org.bouncycastle.jcajce.provider.digest.** { *; }
-keep class org.bouncycastle.jcajce.provider.symmetric.** { *; }
-keep class org.bouncycastle.jcajce.provider.asymmetric.util.** { *; }
-keep class org.bouncycastle.crypto.CryptoServiceProperties { *; }
-keep class org.bouncycastle.jcajce.provider.symmetric.util.ClassUtil { *; }
