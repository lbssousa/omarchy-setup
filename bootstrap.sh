#!/usr/bin/env bash
# Instala o `just` via pacman, caso ainda não esteja disponível — o
# único pré-requisito para conseguir rodar qualquer receita deste
# repositório (`just setup`, `just ptbr`, etc.), já que sem o `just` no
# PATH não dá nem para chegar até as receitas `_ensure-*` do Justfile.
# As demais dependências (ansible, collection community.general) já são
# resolvidas sozinhas por essas receitas na primeira execução — este
# script não duplica essa lógica, só resolve esse primeiro passo.
set -euo pipefail

if command -v just >/dev/null; then
    echo "just já está instalado ($(command -v just))."
else
    echo "just não encontrado; instalando via pacman..."
    sudo pacman -S --needed --noconfirm just
fi

echo "Pronto. Rode 'just setup' para aplicar as automações (ou 'just --list' para ver as receitas disponíveis)."
