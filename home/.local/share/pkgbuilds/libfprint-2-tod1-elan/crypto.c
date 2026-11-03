/* libcrypto.so.1.1 for Lenovo's Elan driver: the nine calls it makes, passed on to OpenSSL 3. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <openssl/evp.h>
#undef EVP_CIPHER_block_size

static void *real(const char *name)
{
    static void *lib;
    void *f;
    if (!lib)
        lib = dlopen("libcrypto.so.3", RTLD_NOW | RTLD_LOCAL);
    f = lib ? dlvsym(lib, name, "OPENSSL_3.0.0") : NULL;
    if (!f)
        abort();
    return f;
}

#define PASS(ret, name, to, params, args)      \
    ret name params                            \
    {                                          \
        static ret(*f) params;                 \
        if (!f)                                \
            f = real(#to);                     \
        return f args;                         \
    }

PASS(const EVP_CIPHER *, EVP_aes_256_cbc, EVP_aes_256_cbc, (void), ())
PASS(const EVP_MD *, EVP_sha256, EVP_sha256, (void), ())
PASS(int, EVP_CIPHER_block_size, EVP_CIPHER_get_block_size, (const EVP_CIPHER *c), (c))
PASS(EVP_CIPHER_CTX *, EVP_CIPHER_CTX_new, EVP_CIPHER_CTX_new, (void), ())
PASS(int, EVP_BytesToKey, EVP_BytesToKey,
     (const EVP_CIPHER *t, const EVP_MD *md, const unsigned char *salt, const unsigned char *data,
      int datal, int count, unsigned char *key, unsigned char *iv),
     (t, md, salt, data, datal, count, key, iv))
PASS(int, EVP_CipherInit_ex, EVP_CipherInit_ex,
     (EVP_CIPHER_CTX *ctx, const EVP_CIPHER *c, ENGINE *e, const unsigned char *key,
      const unsigned char *iv, int enc),
     (ctx, c, e, key, iv, enc))
PASS(int, EVP_CipherUpdate, EVP_CipherUpdate,
     (EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl),
     (ctx, out, outl, in, inl))
PASS(int, EVP_CipherFinal_ex, EVP_CipherFinal_ex, (EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl),
     (ctx, out, outl))

void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *ctx)
{
    static void (*f)(EVP_CIPHER_CTX *);
    if (!f)
        f = real("EVP_CIPHER_CTX_free");
    f(ctx);
}
