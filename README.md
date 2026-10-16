# Italicode

Italicode è un progetto per creare e far eseguire un piccolo linguaggio di programmazione pseudo-codice in italiano.

## Obiettivo

L'idea è avere un linguaggio semplice, leggibile e vicino al pseudocodice, utile per sperimentare come funzionano le fasi di compilazione ed esecuzione di un interprete. Utile per istruzione e scuole.

## Prerequisiti

Per compilare il progetto serve il compilatore D e il tool `dub`. Altrimenti scaricare l'ultimo binaro da [![Latest Release](https://img.shields.io/github/v/release/Felix550/Italicode?label=latest%20release)](https://github.com/Felix550/Italicode/releases/latest)

## Avvio rapido

Da cartella del progetto:

```bash
dub run -- path/del/tuo_file.ic
```

oppure se hai a disposizione il binario:

```bash
italicode.exe path/del/tuo_file.ic
```

## Esempio

Nel file `main.ic` è presente un esempio semplice:

```text
inizio
    scrivi "Ciao, Mondo!\n"
fine
```

## Licenza

Questo progetto è distribuito con licenza GNU GENERAL PUBLIC LICENSE.
[![License](https://img.shields.io/github/license/Felix550/Italicode)](LICENSE)
