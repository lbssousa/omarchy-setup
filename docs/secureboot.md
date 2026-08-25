# `just secureboot` — Secure Boot (Limine + sbctl)

Guia de uso do `playbooks/secureboot.yml`. Diferente de todo o resto
deste repositório, **este playbook não faz parte de `just setup`** —
mexe em firmware/boot, então só roda se você chamar explicitamente
`just secureboot` (ou
`ansible-playbook playbooks/secureboot.yml --ask-become-pass`).
Veja o cabeçalho do próprio playbook para a versão comentada linha a
linha; este documento é o passo a passo de uso.

## Por que existe

Habilitar Secure Boot com chaves próprias (não as da Microsoft) é algo
que o instalador do Omarchy não faz sozinho — cada usuário decide se
quer isso e assume o risco. Este playbook automatiza a parte que dá
para automatizar (instalar o `sbctl`, criar as chaves, configurar o
`limine-entry-tool` para manter tudo assinado, matricular as chaves no
firmware quando possível) e é explícito sobre a parte que **não** dá
(trocar o estado do Secure Boot no firmware exige entrar no BIOS/UEFI
manualmente — nenhum software rodando no Linux consegue fazer isso
pelo usuário).

## Pré-requisitos

- Bootloader **Limine** com o pacote `limine-mkinitcpio-hook`
  (`limine-entry-tool`) instalado — padrão em qualquer instalação do
  Omarchy. O playbook falha cedo, sem mexer em nada, se detectar outro
  bootloader (GRUB, systemd-boot).
- Acesso físico à máquina para entrar no BIOS/UEFI duas vezes durante
  o processo (veja o passo a passo abaixo) — não dá para fazer isso
  remotamente via SSH.
- `sudo` com senha interativa.

## Como funciona (resumo técnico)

Baseado em duas fontes — veja `Créditos` no `README.md` principal para
os links:

1. **Discussões do Omarchy no GitHub** (basecamp/omarchy#5306, #7462)
   descrevem um processo manual (extrair o binário do cache do pacman,
   `limine enroll-config` manual, `sbctl sign -s`, em ordem estrita, e
   repetir tudo a cada kernel novo). Esse processo parece anterior ao
   `limine-entry-tool` ganhar suporte nativo a isso: o código-fonte
   real (`/usr/lib/limine/limine-common-functions`) mostra que, uma
   vez que o `sbctl` tenha chaves criadas, **qualquer operação do
   limine-entry-tool já re-assina o binário do Limine sozinha**
   (inclusive a disparada pelo hook de atualização de kernel do
   pacman) — não é preciso reimplementar aquele processo manual.
2. **[lbssousa/nix-config](https://github.com/lbssousa/nix-config)**
   (`scripts/setup-secureboot.sh`) — de onde vieram a ordem
   assinar-antes-de-matricular chaves, a detecção de Setup Mode lendo
   a variável EFI diretamente (mais robusta que só o texto do `sbctl
   status`), e o desbloqueio de variáveis EFI marcadas imutáveis que
   alguns firmwares aplicam mesmo em Setup Mode.

Com Limine, **não há shim nem MOK/MOKmanager** — o firmware verifica
diretamente a assinatura PE do binário do Limine; o kernel e o
initramfs são protegidos por um checksum BLAKE2b embutido nesse mesmo
binário (`limine enroll-config`), não por assinatura individual.

## Passo a passo

O fluxo tem duas execuções do playbook, com uma ida ao BIOS no meio —
rode `just secureboot` a mesma forma nas duas vezes; o playbook detecta
sozinho em qual etapa você está.

### 1ª execução — preparação

```bash
just secureboot
```

Com o Secure Boot desligado (estado atual normal), o playbook:

1. Confirma que o bootloader é Limine + limine-entry-tool.
2. Instala o `sbctl`.
3. Avisa (sem remover nada) se encontrar `splash` no cmdline do
   kernel — incompatível com Secure Boot nesta configuração, segundo
   basecamp/omarchy#5306.
4. Cria as chaves do `sbctl` (`sbctl create-keys`), se ainda não
   existirem.
5. Liga `ENABLE_ENROLL_LIMINE_CONFIG=yes` e `ENABLE_VERIFICATION=yes`
   em `/etc/default/limine`, e `hash_mismatch_panic: yes` em
   `/boot/limine.conf`.
6. Roda `limine-update` — que já assina o binário do Limine com as
   chaves recém-criadas (mecanismo nativo do limine-entry-tool, veja
   acima).
7. Mostra `sbctl status` e `sbctl verify` para você conferir.
8. Detecta que o firmware **não está em Setup Mode** (via a variável
   EFI `SetupMode`) e para aí, com instruções.

### Ida ao BIOS (1ª vez) — entrar em Setup Mode

1. Reinicie e entre no BIOS/UEFI (a tecla varia por fabricante — F2,
   F12, Del ou Esc durante o boot).
2. Vá em **Secure Boot** e procure uma opção como *"Setup Mode"*,
   *"Clear Secure Boot Keys"* ou *"Delete All Secure Boot Keys"*.
3. Limpe/apague as chaves existentes — isso ativa o Setup Mode.
4. Salve e reinicie de volta para o Linux.

### 2ª execução — matrícula das chaves

```bash
just secureboot
```

Desta vez o playbook detecta o Setup Mode e:

1. Desbloqueia variáveis EFI marcadas imutáveis, se necessário (alguns
   firmwares fazem isso mesmo em Setup Mode).
2. Matricula as chaves no firmware: `sbctl enroll-keys --microsoft`
   (inclui as chaves da Microsoft, para compatibilidade com
   drivers/firmware assinados por ela).
3. Mostra o resultado e as instruções finais.

### Ida ao BIOS (2ª vez) — ligar o Secure Boot

1. Reinicie, entre no BIOS/UEFI de novo.
2. **Ligue** o Secure Boot.
3. Salve e reinicie.

### Verificação final

```bash
sbctl status      # deve mostrar "Secure Boot: enabled"
bootctl status    # idem, na seção "Secure Boot"
```

Se a máquina não bootar com o Secure Boot ligado, veja
[Se o boot falhar](#se-o-boot-falhar) abaixo.

## Avisos importantes

- **`splash` (Plymouth) no cmdline do kernel** quebra o boot com
  Secure Boot ligado nesta configuração, segundo
  basecamp/omarchy#5306. O playbook avisa se encontrar, mas não
  remove — decida e edite `/etc/default/limine` manualmente se for o
  seu caso, e rode `sudo limine-update` depois.
- **LUKS com desbloqueio automático via TPM2**: se você usa isso
  (`systemd-cryptenroll --tpm2-pcrs=...`), ligar o Secure Boot pela
  primeira vez muda o PCR7 (estado do Secure Boot) e quebra o
  desbloqueio automático até você re-matricular o TPM2:
  ```bash
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7 /dev/<partição-luks>
  ```
  A senha continua funcionando como fallback nesse meio tempo — não é
  risco de ficar trancado para fora, só um lembrete para não se
  assustar se o desbloqueio automático parar de funcionar depois do
  primeiro boot com Secure Boot ativo.
- **`hash_mismatch_panic: yes`** (que este playbook liga) faz o boot
  travar se o checksum do kernel/initrd não bater com o que está
  embutido no binário do Limine. É a proteção de integridade real do
  Secure Boot aqui — mas também significa que editar manualmente
  qualquer arquivo de boot sem passar pelo `limine-entry-tool` depois
  (ex.: rodar `limine-update` ou `sudo limine-enroll-config`) quebra o
  boot.

## Se o boot falhar

Sistemas com Secure Boot mal configurado tipicamente não bootam de
jeito nenhum (tela preta ou um panic do Limine) em vez de bootar
parcialmente — não há risco de "meio quebrado". Recuperação:

1. Reinicie e entre no BIOS/UEFI.
2. **Desligue** o Secure Boot de novo. Isso por si só já deve
   restaurar o boot (o firmware para de verificar assinaturas).
3. Do Linux, rode `sbctl verify` para ver quais binários não estão
   assinados corretamente, e `sudo limine-update` para forçar uma
   nova assinatura.
4. Repita o passo a passo acima a partir de onde parou.

Nenhum arquivo do sistema em si é apagado por esse processo — o pior
cenário é não conseguir religar o Secure Boot até corrigir a causa,
não perder dados nem precisar reinstalar.

## Rodando de novo

O playbook é idempotente: rodar `just secureboot` de novo numa máquina
que já tem tudo configurado só confirma o estado (chaves já existem,
config já está com os flags certos) e não deveria fazer nada novo,
exceto o próprio `limine-update` (que sempre roda, é seguro/idempotente
por design da ferramenta).
