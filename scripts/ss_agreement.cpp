#include <cstdio>
#include <iostream>
#include <map>
#include <string>
#include <tuple>
#include <vector>

#include <gemmi/mmread.hpp>
#include <gemmi/gz.hpp>
#include <gemmi/model.hpp>
#include <gemmi/metadata.hpp>

#include "Atom.hpp"
#include "SSPredictor.hpp"

struct Counts {
    long total = 0;
    long agree = 0;
    long ann_h = 0, ann_s = 0, ann_c = 0;
    long pred_h = 0, pred_s = 0, pred_c = 0;
    long hit_h = 0, hit_s = 0, hit_c = 0;
};

static void accumulate(Counts& c, char ann, char pred) {
    c.total++;
    if (ann == pred) c.agree++;
    if (ann == 'H') c.ann_h++;
    else if (ann == 'S') c.ann_s++;
    else c.ann_c++;
    if (pred == 'H') c.pred_h++;
    else if (pred == 'S') c.pred_s++;
    else c.pred_c++;
    if (ann == pred) {
        if (ann == 'H') c.hit_h++;
        else if (ann == 'S') c.hit_s++;
        else c.hit_c++;
    }
}

static std::string pct(long num, long den) {
    if (den <= 0) return "-";
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%.1f", 100.0 * (double)num / (double)den);
    return buf;
}

static void print_row(const std::string& label, const Counts& c) {
    std::printf("%-26s %7ld %8s %8s %8s %8s %8s %8s\n",
                label.c_str(), c.total,
                pct(c.agree, c.total).c_str(),
                pct(c.hit_h, c.ann_h).c_str(), pct(c.hit_h, c.pred_h).c_str(),
                pct(c.hit_s, c.ann_s).c_str(), pct(c.hit_s, c.pred_s).c_str(),
                pct(c.hit_c, c.ann_c).c_str());
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::printf("usage: ss_agreement <structure files...>\n");
        return 2;
    }

    std::printf("%-26s %7s %8s %8s %8s %8s %8s %8s\n",
                "structure", "res", "agree%", "H_recall", "H_prec", "S_recall", "S_prec", "C_recall");

    Counts total;
    int used = 0;
    for (int i = 1; i < argc; i++) {
        const std::string path = argv[i];
        gemmi::Structure st;
        try {
            st = gemmi::read_structure(gemmi::MaybeGzipped(path));
        } catch (const std::exception& e) {
            std::fprintf(stderr, "skip %s: %s\n", path.c_str(), e.what());
            continue;
        }
        st.remove_empty_chains();
        st.merge_chain_parts();

        if (st.helices.empty() && st.sheets.empty()) {
            std::fprintf(stderr, "skip %s: no HELIX/SHEET annotation\n", path.c_str());
            continue;
        }

        std::vector<std::tuple<std::string, int, int, char>> ranges;
        for (const gemmi::Helix& h : st.helices) {
            if (!h.start.res_id.seqid.num.has_value() || !h.end.res_id.seqid.num.has_value())
                continue;
            const std::string cid = h.start.chain_name.empty() ? "?" : h.start.chain_name;
            ranges.emplace_back(cid, (int)h.start.res_id.seqid.num,
                                (int)h.end.res_id.seqid.num, 'H');
        }
        for (const gemmi::Sheet& sheet : st.sheets) {
            for (const gemmi::Sheet::Strand& s : sheet.strands) {
                if (!s.start.res_id.seqid.num.has_value() || !s.end.res_id.seqid.num.has_value())
                    continue;
                const std::string cid = s.start.chain_name.empty() ? "?" : s.start.chain_name;
                ranges.emplace_back(cid, (int)s.start.res_id.seqid.num,
                                    (int)s.end.res_id.seqid.num, 'S');
            }
        }

        std::map<std::string, std::vector<Atom>> atoms;
        std::map<std::string, std::vector<char>> annotation;
        gemmi::Model& model = st.first_model();
        for (gemmi::Chain& chain : model.chains) {
            const std::string cid = chain.name.empty() ? "?" : chain.name;
            for (gemmi::Residue& res : chain.residues) {
                const gemmi::Atom* ca = res.get_ca();
                if (!ca) continue;
                if (!res.seqid.num.has_value()) continue;
                const int resn = (int)res.seqid.num;

                Atom a((float)ca->pos.x, (float)ca->pos.y, (float)ca->pos.z, 'x');
                a.residue_number = resn;
                a.residue_name = res.name;
                atoms[cid].push_back(a);

                char ann = 'x';
                for (const auto& r : ranges) {
                    if (std::get<0>(r) == cid && resn >= std::get<1>(r) && resn <= std::get<2>(r)) {
                        ann = std::get<3>(r);
                        break;
                    }
                }
                annotation[cid].push_back(ann);
            }
        }

        SSPredictor predictor;
        {
            std::streambuf* saved = std::cout.rdbuf(nullptr);
            predictor.run(atoms);
            std::cout.rdbuf(saved);
        }

        Counts c;
        for (const auto& [cid, chain_atoms] : atoms) {
            const std::vector<char>& ann = annotation[cid];
            for (size_t k = 0; k < chain_atoms.size() && k < ann.size(); k++) {
                accumulate(c, ann[k], chain_atoms[k].get_structure());
            }
        }
        if (c.total == 0) continue;

        std::string label = path;
        const size_t slash = label.find_last_of('/');
        if (slash != std::string::npos) label = label.substr(slash + 1);
        print_row(label, c);

        total.total += c.total;   total.agree += c.agree;
        total.ann_h += c.ann_h;   total.ann_s += c.ann_s;   total.ann_c += c.ann_c;
        total.pred_h += c.pred_h; total.pred_s += c.pred_s; total.pred_c += c.pred_c;
        total.hit_h += c.hit_h;   total.hit_s += c.hit_s;   total.hit_c += c.hit_c;
        used++;
    }

    if (used > 0) {
        std::printf("%-26s %7s %8s %8s %8s %8s %8s %8s\n", "", "", "", "", "", "", "", "");
        print_row("ALL", total);
    }
    return used > 0 ? 0 : 1;
}
