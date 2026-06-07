/*
 *  COpenJTalk implementation — drives the vendored Open JTalk frontend.
 *
 *  Mirrors pyopenjtalk's `run_frontend` pipeline (openjtalk.pyx): one Mecab
 *  dictionary load on create, then per call:
 *      text2mecab → Mecab_analysis → mecab2njd → njd_set_pronunciation →
 *      njd_set_digit → njd_set_accent_phrase → njd_set_accent_type →
 *      njd_set_unvoiced_vowel → njd_set_long_vowel
 *  then walk the NJD node list reading pron/acc/mora_size/chain_flag/string/pos.
 *
 *  jpcommon / njd2jpcommon (full-context labels) and hts_engine are intentionally
 *  not used here — Kokoro synthesizes the audio; we only need readings + accent.
 */

#include "copenjtalk.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "mecab.h"
#include "njd.h"
#include "text2mecab.h"
#include "mecab2njd.h"
#include "njd_set_pronunciation.h"
#include "njd_set_digit.h"
#include "njd_set_accent_phrase.h"
#include "njd_set_accent_type.h"
#include "njd_set_unvoiced_vowel.h"
#include "njd_set_long_vowel.h"

struct ojt_frontend {
    Mecab mecab;
    NJD njd;
};

ojt_frontend *ojt_frontend_create(const char *dicdir) {
    if (dicdir == nullptr) {
        return nullptr;
    }
    ojt_frontend *fe = new (std::nothrow) ojt_frontend();
    if (fe == nullptr) {
        return nullptr;
    }
    Mecab_initialize(&fe->mecab);
    NJD_initialize(&fe->njd);
    if (Mecab_load(&fe->mecab, dicdir) != TRUE) {
        Mecab_clear(&fe->mecab);
        NJD_clear(&fe->njd);
        delete fe;
        return nullptr;
    }
    return fe;
}

void ojt_frontend_destroy(ojt_frontend *fe) {
    if (fe == nullptr) {
        return;
    }
    Mecab_clear(&fe->mecab);
    NJD_clear(&fe->njd);
    delete fe;
}

static char *dup_cstr(const char *s) {
    if (s == nullptr) {
        s = "";
    }
    size_t len = std::strlen(s);
    char *out = static_cast<char *>(std::malloc(len + 1));
    if (out != nullptr) {
        std::memcpy(out, s, len + 1);
    }
    return out;
}

ojt_result ojt_run_frontend(ojt_frontend *fe, const char *text) {
    ojt_result empty;
    empty.words = nullptr;
    empty.count = 0;

    if (fe == nullptr || text == nullptr || text[0] == '\0') {
        return empty;
    }

    // text2mecab escapes/expands characters; size generously for the worst case.
    size_t inputLen = std::strlen(text);
    std::vector<char> buff(inputLen * 8 + 1024, '\0');
    text2mecab(buff.data(), text);

    Mecab_analysis(&fe->mecab, buff.data());
    mecab2njd(&fe->njd, Mecab_get_feature(&fe->mecab), Mecab_get_size(&fe->mecab));
    njd_set_pronunciation(&fe->njd);
    njd_set_digit(&fe->njd);
    njd_set_accent_phrase(&fe->njd);
    njd_set_accent_type(&fe->njd);
    njd_set_unvoiced_vowel(&fe->njd);
    njd_set_long_vowel(&fe->njd);

    std::vector<ojt_word> collected;
    for (NJDNode *node = fe->njd.head; node != nullptr; node = node->next) {
        ojt_word w;
        w.surface = dup_cstr(NJDNode_get_string(node));
        w.pron = dup_cstr(NJDNode_get_pron(node));
        w.pos = dup_cstr(NJDNode_get_pos(node));
        w.acc = NJDNode_get_acc(node);
        w.mora_size = NJDNode_get_mora_size(node);
        w.chain_flag = NJDNode_get_chain_flag(node);
        collected.push_back(w);
    }

    // Release the per-call NJD/Mecab working state (matches pyopenjtalk).
    NJD_refresh(&fe->njd);
    Mecab_refresh(&fe->mecab);

    if (collected.empty()) {
        return empty;
    }

    ojt_result result;
    result.count = collected.size();
    result.words = static_cast<ojt_word *>(std::malloc(sizeof(ojt_word) * collected.size()));
    if (result.words == nullptr) {
        for (auto &w : collected) {
            std::free(const_cast<char *>(w.surface));
            std::free(const_cast<char *>(w.pron));
            std::free(const_cast<char *>(w.pos));
        }
        return empty;
    }
    std::memcpy(result.words, collected.data(), sizeof(ojt_word) * collected.size());
    return result;
}

void ojt_result_free(ojt_result result) {
    if (result.words == nullptr) {
        return;
    }
    for (size_t i = 0; i < result.count; ++i) {
        std::free(const_cast<char *>(result.words[i].surface));
        std::free(const_cast<char *>(result.words[i].pron));
        std::free(const_cast<char *>(result.words[i].pos));
    }
    std::free(result.words);
}
