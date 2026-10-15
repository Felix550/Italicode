#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
from typing import Iterable

LANG_ID = "italicode"
LANG_NAME = "italicode"
FILE_GLOB = "*.ic"
MIME_TYPE = "text/x-italicode"

KEYWORDS = [
    "dichiara", "assegna", "calcola", "scrivi", "leggi", "immetti",
    "inizio", "fine", "se", "esegui", "mentre", "ripeti", "allora",
    "altrimenti", "continua", "ferma", "per", "da", "passo",
    "funzione", "ritorna",
    "Vero", "Falso", "True", "False", "vero", "falso", "true", "false"
]

TYPES = [
    "intero", "reale", "stringa", "booleano",
    "Intero", "Reale", "Stringa", "Booleano"
]

BOOLS = [
    "vero", "falso", "true", "false",
    "Vero", "Falso", "True", "False"
]

IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_]*"


def gedit_language() -> str:
    keywords = "\n          ".join(f'<keyword>{k}</keyword>' for k in KEYWORDS)
    types = "\n          ".join(f'<keyword>{t}</keyword>' for t in TYPES)

    return f'''<?xml version="1.0" encoding="UTF-8"?>
<language id="{LANG_ID}" name="{LANG_NAME}" version="2.0" _section="Source">
  <metadata>
    <property name="mimetypes">{MIME_TYPE}</property>
    <property name="globs">{FILE_GLOB}</property>
    <property name="line-comment-start">#</property>
  </metadata>
  <styles>
    <style id="keyword" name="Keyword" map-to="def:keyword"/>
    <style id="type" name="Type" map-to="def:type"/>
    <style id="boolean" name="Boolean" map-to="def:boolean"/>
    <style id="string" name="String" map-to="def:string"/>
    <style id="number" name="Number" map-to="def:decimal"/>
    <style id="comment" name="Comment" map-to="def:comment"/>
    <style id="operator" name="Operator" map-to="def:operator"/>
    <style id="function-call" name="Function Call" map-to="def:function"/>
    <style id="grouped-expression" name="Grouped Expression" map-to="def:identifier"/>
  </styles>
  <definitions>
    <context id="{LANG_ID}">
      <include>
        <context id="comment" style-ref="comment" end-at-line-end="true">
          <start>#</start>
          <end>\\n</end>
        </context>
        <context id="strings-double" style-ref="string" class="string" class-disabled="no-spell-check">
          <start>"</start>
          <end>"</end>
          <include>
            <context ref="def:escape"/>
            <context ref="def:line-continue"/>
          </include>
        </context>
        <context id="strings-single" style-ref="string" class="string" class-disabled="no-spell-check">
          <start>'</start>
          <end>'</end>
          <include>
            <context ref="def:escape"/>
            <context ref="def:line-continue"/>
          </include>
        </context>
        
        <context id="parentheses" style-ref="parenthesis">
          <match>[\(\)]</match>
        </context>

        <context id="square-brackets" style-ref="square-bracket">
          <match>[\[\]]</match>
        </context>

        <context id="numbers" style-ref="number">
          <match>(?&lt;![\\w\\\\.])((0[xX][0-9A-Fa-f]+)|([0-9]+(\\\\.[0-9]+)?([eE][+-]?[0-9]+)?))(?![\\w\\\\.])</match>
        </context>
        <context id="operators" style-ref="operator">
          <match>(==|!=|&lt;=|&gt;=|\\\\+|\\\\-|\\\\*|/|%|=|&lt;|&gt;|!|&amp;&amp;|\\\\|\\\\||&amp;|\\\\||\\\\^|\\~|\\\\-&gt;)</match>
        </context>
        <context id="function-call" style-ref="function-call">
          <match>(?&lt;![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\\s*(?=\\()</match>
        </context>
        <context id="grouped-expression" style-ref="grouped-expression">
          <match>\\([^\\)]*\\)</match>
        </context>
        <context id="keywords" style-ref="keyword">
          {keywords}
        </context>
        <context id="types" style-ref="type">
          {types}
        </context>
      </include>
    </context>
  </definitions>
</language>
'''


def vscode_grammar() -> dict:
    def regex_group(values: Iterable[str]) -> str:
        return "|".join(sorted(set(values), key=len, reverse=True))

    return {
        "$schema": "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
        "name": LANG_NAME,
        "scopeName": "source.italicode",
        "fileTypes": ["ic"],
        "patterns": [
            {"include": "#comments"},
            {"include": "#strings"},
            {"include": "#numbers"},
            {"include": "#operators"},
            {"include": "#keywords"},
            {"include": "#types"},
            {"include": "#booleans"},
            {"include": "#function-call"},
            {"include": "#parenthesized-expression"},
            {"include": "#identifiers"},
        ],
        "repository": {
            "comments": {
                "patterns": [
                    {"match": "#.*$", "name": "comment.line.number-sign.italicode"}
                ]
            },
            "strings": {
                "patterns": [
                    {
                        "name": "string.quoted.double.italicode",
                        "begin": '"',
                        "end": '"',
                        "patterns": [
                            {"match": r"\\.", "name": "constant.character.escape.italicode"},
                            {"match": r"\{[A-Za-z_][A-Za-z0-9_]*\}", "name": "variable.interpolation.italicode"},
                        ],
                    },
                    {
                        "name": "string.quoted.single.italicode",
                        "begin": "'",
                        "end": "'",
                        "patterns": [
                            {"match": r"\\.", "name": "constant.character.escape.italicode"},
                            {"match": r"\{[A-Za-z_][A-Za-z0-9_]*\}", "name": "variable.interpolation.italicode"},
                        ],
                    },
                ]
            },
            "numbers": {
                "patterns": [
                    {
                        "match": r"(?<![\w\.])-?(?:0[xX][0-9A-Fa-f]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)(?![\w\.])",
                        "name": "constant.numeric.italicode",
                    }
                ]
            },
            "operators": {
                "patterns": [
                    {
                        "match": r"==|!=|<=|>=|\+|-|\*|/|%|=|<|>|!|&&|\|\||&|\||\^|~|->",
                        "name": "keyword.operator.italicode",
                    }
                ]
            },
            "keywords": {
                "patterns": [
                    {
                        "match": rf"\b(?:{regex_group(KEYWORDS)})\b",
                        "name": "keyword.control.italicode",
                    }
                ]
            },
            "types": {
                "patterns": [
                    {
                        "match": rf"\b(?:{regex_group(TYPES)})\b",
                        "name": "storage.type.italicode",
                    }
                ]
            },
            "booleans": {
                "patterns": [
                    {
                        "match": rf"\b(?:{regex_group(BOOLS)})\b",
                        "name": "constant.language.boolean.italicode",
                    }
                ]
            },
            "identifiers": {
                "patterns": [
                    {"match": rf"\b{IDENTIFIER}\b", "name": "variable.other.italicode"}
                ]
            },
            "function-call": {
                "patterns": [
                    {
                        "match": rf"\b({IDENTIFIER})\s*(?=\()",
                        "captures": {
                            "1": {"name": "entity.name.function.italicode"}
                        },
                        "name": "meta.function-call.italicode",
                    }
                ]
            },
            "parenthesized-expression": {
                "patterns": [
                    {"match": r"\([^)]*\)", "name": "meta.group.italicode"}
                ]
            },
        },
    }


def vscode_extension_package() -> dict:
    return {
        "name": "italicode-syntax",
        "displayName": "italicode Syntax",
        "version": "0.1.0",
        "engines": {"vscode": "^1.80.0"},
        "contributes": {
            "languages": [
                {
                    "id": LANG_ID,
                    "aliases": [LANG_NAME, "italicode"],
                    "extensions": [".ic"],
                    "mimetypes": [MIME_TYPE],
                }
            ],
            "grammars": [
                {
                    "language": LANG_ID,
                    "scopeName": "source.italicode",
                    "path": "./syntaxes/italicode.tmLanguage.json",
                }
            ],
        },
    }


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def write_gedit_install(base_dir: Path) -> Path:
    out = base_dir / "italicode.lang"
    write_file(out, gedit_language())
    return out


def write_vscode_install(base_dir: Path) -> Path:
    syntax_dir = base_dir / "syntaxes"

    write_file(
        syntax_dir / "italicode.tmLanguage.json",
        json.dumps(vscode_grammar(), indent=2, ensure_ascii=False) + "\n"
    )

    write_file(
        base_dir / "package.json",
        json.dumps(vscode_extension_package(), indent=2, ensure_ascii=False) + "\n"
    )

    write_file(
        base_dir / "language-configuration.json",
        json.dumps({
            "comments": {"lineComment": "#"},
            "brackets": [["(", ")"], ["[", "]"], ["{", "}"]],
            "autoClosingPairs": [
                {"open": "\"", "close": "\""},
                {"open": "'", "close": "'"},
                {"open": "(", "close": ")"},
                {"open": "[", "close": "]"},
                {"open": "{", "close": "}"},
            ],
            "surroundingPairs": [
                {"open": "\"", "close": "\""},
                {"open": "'", "close": "'"},
                {"open": "(", "close": ")"},
                {"open": "[", "close": "]"},
                {"open": "{", "close": "}"},
            ],
        }, indent=2, ensure_ascii=False) + "\n"
    )

    return syntax_dir / "italicode.tmLanguage.json"


def main() -> None:
    workspace = Path(__file__).resolve().parent

    gedit_dir = (
        Path.home()
        / ".local/share/libgedit-gtksourceview-300/language-specs"
    )

    vscode_dir = workspace / "vscode-italicode"

    write_gedit_install(gedit_dir)
    print(f"Generated gedit syntax: {gedit_dir / 'italicode.lang'}")

    write_vscode_install(vscode_dir)
    print(f"Generated VS Code grammar: {vscode_dir / 'syntaxes/italicode.tmLanguage.json'}")
    print("Done.")


if __name__ == "__main__":
    main()