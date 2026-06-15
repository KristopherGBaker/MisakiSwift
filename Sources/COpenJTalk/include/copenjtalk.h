/*
 *  COpenJTalk — a thin C interface over the Open JTalk text-processing frontend.
 *
 *  This exposes only what MisakiSwift's `OpenJTalkG2P` needs: run the morphological
 *  + accent analysis frontend (text2mecab → mecab → mecab2njd → njd_set_*) and read
 *  back, per NJD word, the katakana reading (`pron`), the accent nucleus mora index
 *  (`acc`), the mora count (`mora_size`), the accent-phrase `chain_flag`, the surface
 *  `string`, and the part-of-speech `pos`. The hts_engine synthesis half of OpenJTalk
 *  is deliberately NOT vendored — Kokoro does the audio.
 *
 *  License: the vendored Open JTalk frontend (Nagoya Institute of Technology / HTS
 *  Working Group) is modified-BSD (3-clause); see openjtalk/COPYING. No GPL.
 */

#ifndef COPENJTALK_H
#define COPENJTALK_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to an initialized frontend (mecab dictionary loaded once, reused).
typedef struct ojt_frontend ojt_frontend;

/// One NJD word from the frontend. All strings are UTF-8 and owned by the result;
/// they are valid until `ojt_result_free` is called.
typedef struct {
    const char *surface;     ///< NJDNode `string` — the source surface form.
    const char *pron;        ///< Katakana pronunciation (the G2P input; phonetic long vowels).
    const char *read;        ///< Katakana orthographic reading (e.g. キョウ vs pron キョー) — for furigana.
    const char *pos;         ///< Part-of-speech (NJDNode `pos`).
    int acc;                 ///< Accent nucleus mora index (1-based; 0 = heiban/flat).
    int mora_size;           ///< Number of moras in `pron`.
    int chain_flag;          ///< Accent-phrase chaining: -1 start / 1 attach / 0 new.
} ojt_word;

/// A run_frontend result: a contiguous array of `count` words.
typedef struct {
    ojt_word *words;
    size_t count;
} ojt_result;

/// Create a frontend, loading the MeCab dictionary at `dicdir` (the UTF-8
/// `open_jtalk_dic` directory). Returns NULL on failure (e.g. dictionary missing).
ojt_frontend *ojt_frontend_create(const char *dicdir);

/// Destroy a frontend created by `ojt_frontend_create`.
void ojt_frontend_destroy(ojt_frontend *fe);

/// Run the text-processing frontend on UTF-8 `text`. The caller owns the returned
/// result and must release it with `ojt_result_free`. Returns a result with
/// `count == 0` (and `words == NULL`) for empty/blank input.
ojt_result ojt_run_frontend(ojt_frontend *fe, const char *text);

/// Release a result returned by `ojt_run_frontend`.
void ojt_result_free(ojt_result result);

#ifdef __cplusplus
}
#endif

#endif /* COPENJTALK_H */
