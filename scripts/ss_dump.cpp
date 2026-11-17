#include "SSPredictor.hpp"

#include <iostream>
#include <map>
#include <string>
#include <vector>

int main() {
    std::map<std::string, std::vector<Atom>> atoms;
    std::vector<std::string> chain_order;

    std::string chain;
    int residue_number;
    float x, y, z;
    while (std::cin >> chain >> residue_number >> x >> y >> z) {
        Atom a(x, y, z);
        a.residue_number = residue_number;
        if (atoms.find(chain) == atoms.end()) chain_order.push_back(chain);
        atoms[chain].push_back(a);
    }

    SSPredictor predictor;
    predictor.run(atoms);

    for (const auto& c : chain_order)
        for (const auto& a : atoms[c])
            std::cerr << c << "\t" << a.residue_number << "\t" << a.get_structure() << "\n";

    return 0;
}
