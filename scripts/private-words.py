#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
"""No name of a maintainer's private folder, person or unannounced project in any public file or commit message
(audit F-16, 09.11.2026). The words are kept here as SHA-256 hashes, so this check does not publish what it looks for.
Reads the file names given on stdin, NUL separated, or with --text the text on stdin. Exit 1 on a hit."""
import hashlib, os, re, sys

HASHES = {
    "2fdd4315931b1ecba55f46888b5ee8f8f44e50ec01ec9de9f025c60424be3af4",
    "31b545a95b61d219aba62aa7832a790c7ab9b67c1b9e1f4dede4bb2c9bbf6ced",
    "3ad20a3deab0d5fae590019f299fe386e79a3dcd24b542833f6c4f0a0bb8d26a",
    "88b6ebcbd7b7ef0a4bfdd3ba6b735d7920d20ce61270b1cb09d4f12d98174b47",
    "900516d71e48d26eee8aabb8b5b4d6ddb209583a909020af5b01e4767c4ca616",
    "bb5c5e69d3aaba654ccd2e742d782790bdd2a138aeb8c373425ad37adc7909bb",
    "cc530122e932743f3eb202a8f4cfd7dea1fa5de0a6291d665f69093712f79319",
    "e77f74c08fb585945ed76c1096d36b8730a377617809f9e2e426d666071dd93a",
    "f14e89800a2162f333461c0c6f78e66046d289dfc62f0d597110cf0f1ce160ce",
    "fd020e334da00352e0adf37d76c2e47a221faedcb9f3f4041cfb240e0cf899cc",
}


def hits(text):
    # the words one by one, and two neighbours joined by a dash for names made of two words
    words = re.findall(r"[a-z0-9]+", text.lower())
    grams = set(words) | {a + "-" + b for a, b in zip(words, words[1:])}
    return sorted(g for g in grams if hashlib.sha256(g.encode()).hexdigest() in HASHES)


if "--text" in sys.argv:
    sys.exit(1 if hits(sys.stdin.read()) else 0)
if "--lines" in sys.argv:
    # the line numbers that hold a private word, one run; the word itself is never printed
    # a line alone, and each line with the one before, so a two word name split over a line break is found too
    ls = sys.stdin.read().split("\n")
    bad = sorted({n for n, l in enumerate(ls, 1) if hits(l)} | {n for n in range(2, len(ls) + 1) if hits(ls[n - 2] + " " + ls[n - 1])})
    print(" ".join(map(str, bad)))
    sys.exit(1 if bad else 0)
bad = 0
for name in sys.stdin.buffer.read().decode().split("\0"):
    if not name or not os.path.isfile(name):
        continue
    data = open(name, "rb").read()
    if b"\0" in data:
        continue
    if hits(data.decode("utf-8", "replace")):
        print(f"private word in {name}")
        bad += 1
sys.exit(1 if bad else 0)
