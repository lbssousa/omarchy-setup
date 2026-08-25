# omarchy-setup

Automação (Ansible) para o setup inicial de um desktop
[Omarchy](https://omarchy.org/) recém-instalado — um Arch Linux comum
(pacman, mutável, sem restrição de `/usr` somente leitura), diferente
do irmão [lbssousa/bluefin-initial-setup](https://github.com/lbssousa/bluefin-initial-setup)
(Fedora Atomic). Aqui não há necessidade de contornar rpm-ostree/Homebrew:
os pacotes são instalados direto via pacman.

Cada automação é um playbook próprio em `playbooks/`, importado por
`site.yml` via `ansible.builtin.import_playbook` — todas rodam dentro
do mesmo `--ask-become-pass`, mas cada uma tem sua própria tag: rode só
uma com `--tags <tag>`, ou pule uma com `--skip-tags <tag>`.

## O que este playbook faz

1. **Localização pt-BR** (`playbooks/ptbr.yml`, tag `ptbr`) — deixa o
   sistema o mais próximo possível de totalmente em português do
   Brasil, em três frentes independentes (sub-tags, cada uma
   selecionável isoladamente):
   - **Locale** (`ptbr-locale`) — habilita `pt_BR.UTF-8 UTF-8` em
     `/etc/locale.gen` (sem remover nenhum locale já habilitado, ex.
     `en_US.UTF-8`), roda `locale-gen`, e define `LANG=pt_BR.UTF-8` em
     `/etc/locale.conf`. `LANGUAGE=pt_BR:pt:en` também é definido — a
     cadeia de fallback do gettext, usada quando um app tem tradução
     pt_BR incompleta mas tem pt genérico (ou nenhuma das duas, caindo
     em inglês em vez de travar em C/POSIX). Nenhuma categoria `LC_*`
     é definida individualmente: todas herdam de `LANG`, igual à troca
     de idioma em Configurações do GNOME. **É preciso fazer logout (ou
     reboot) depois**, para o Hyprland e os apps já abertos assumirem
     o novo idioma — o playbook avisa isso ao final, mas não reinicia
     a sessão sozinho.
   - **Pastas pessoais / xdg-user-dirs** (`ptbr-xdg-user-dirs`) —
     renomeia `~/Downloads`, `~/Documents` etc. para os nomes
     traduzidos oficiais do
     [xdg-user-dirs](https://www.freedesktop.org/wiki/Software/xdg-user-dirs/)
     em pt_BR (Área de Trabalho, Downloads, Modelos, Público,
     Documentos, Música, Imagens, Vídeos), **incluindo** `~/Projects`
     → `~/Projetos` (`XDG_PROJECTS_DIR`, entrada extra do Omarchy em
     `/etc/xdg/user-dirs.defaults`, fora do padrão upstream do
     xdg-user-dirs — mas testamos e `xdg-user-dirs-update --set` aceita
     esse nome sem reclamar, apesar do manual só listar os 8 nomes
     padrão), só para as pastas que já estiverem habilitadas — se Área
     de Trabalho/Modelos/Público estiverem desabilitadas
     (`XDG_*_DIR="$HOME/"`, como costuma ser preferência pessoal),
     permanecem desabilitadas. O comando `xdg-user-dirs-update`,
     sozinho, **nunca** renomeia pastas já existentes — ele só cria as
     que ainda não têm entrada em `user-dirs.dirs`; quem faz esse
     rename (com diálogo de confirmação) é o
     `xdg-user-dirs-gtk-update`, uma ferramenta gráfica que não dá para
     rodar de forma não interativa. Este playbook replica manualmente
     o mesmo mecanismo (`mv` + `xdg-user-dirs-update --set`), sem
     diálogo, e só renomeia se a pasta ainda não estiver com o nome
     traduzido — idempotente, seguro rodar de novo. Uma pasta
     desabilitada é gravada em `user-dirs.dirs` como `"$HOME/"` literal
     (com barra final); a comparação normaliza essa barra antes de
     decidir se a pasta está desabilitada — sem isso, o playbook tenta
     mover `$HOME` para dentro de si mesmo (bug corrigido depois do
     primeiro uso real deste playbook).
   - **Firefox** (`ptbr-firefox`) — instala o pacote
     `firefox-i18n-pt-br` via pacman, **se o Firefox estiver
     instalado** (senão pula, sem falhar — o instalador do Omarchy
     permite escolher outro navegador padrão, ex. Chromium). Com
     `LANG=pt_BR.UTF-8` e o pacote de idioma instalado, o Firefox
     escolhe pt-BR sozinho no próximo perfil — mesmo mecanismo de
     qualquer Firefox empacotado por distro Linux. De propósito, este
     playbook não mexe em `about:config` nem em políticas corporativas
     (`policies.json`): dependeria do layout interno do pacote
     `firefox` do Arch, é frágil a atualizações, e sobrescreveria
     silenciosamente uma escolha de idioma que o usuário já tenha
     feito manualmente no navegador.

   **Fora do escopo, de propósito**: layout de teclado e fuso horário
   — ambos já são perguntados pelo próprio instalador do Omarchy
   (`install/provisioning/setup-form.sh`), então mexer neles aqui seria
   redundante (ou pior, conflitante com uma escolha já feita).
2. **Bitwarden** (`playbooks/bitwarden.yml`, tag `bitwarden`) — instala
   o cliente desktop do Bitwarden, escolhendo a origem do pacote
   **dinamicamente a cada execução**: prefere `bitwarden-bin` do AUR
   (o pacote oficial do Arch, `extra/bitwarden`, costuma ficar meses
   atrás da versão do AUR), mas volta a usar o pacote oficial sozinho
   assim que ele deixar de estar desatualizado em relação ao AUR — a
   decisão é feita comparando as duas versões via `vercmp` (a mesma
   lógica do próprio pacman), não uma escolha fixa no playbook. Os dois
   pacotes se conflitam (não dá pra ter os dois instalados ao mesmo
   tempo); o playbook desinstala o outro automaticamente ao trocar de
   origem.

   Como o `makepkg` chamaria `sudo` internamente para sincronizar
   dependências em falta — e esse `sudo` pediria uma senha interativa
   que o Ansible não tem como responder sem travar —, o playbook nunca
   deixa o processo de build lidar com privilégios sozinho. Em vez
   disso, cada etapa privilegiada roda
   via `become: true` (a mesma senha de `--ask-become-pass`): as
   dependências de runtime do bitwarden-bin são instaladas via pacman
   *antes* do build (evitando o `--syncdeps` do makepkg), o repositório
   AUR é só clonado com `git` (sem privilégio nenhum), o `makepkg
   --nodeps` builda como usuário normal (makepkg recusa rodar como
   root), e só a instalação final do pacote já buildado (`pacman -U`)
   usa `become: true` de novo.

   Depois de instalado, o playbook também liga o `SSH_AUTH_SOCK`
   padrão da sessão ao agente SSH do Bitwarden — importado de
   [lbssousa/bluefin-initial-setup](https://github.com/lbssousa/bluefin-initial-setup)
   (mesmo mecanismo: `~/.config/environment.d/` para a camada estática
   + um `.path` unit systemd --user que reage à criação do socket),
   mas com o caminho do socket ajustado para uma instalação nativa
   (pacman/AUR, sem sandbox Flatpak): `~/.bitwarden-ssh-agent.sock`
   direto na home, e não `~/.var/app/com.bitwarden.desktop/...` (que só
   existe dentro do sandbox do Flatpak) — confirmado pela
   [documentação oficial](https://bitwarden.com/help/ssh-agent/). Como
   lá, o `gcr-ssh-agent` (aqui do pacote `gcr-4`) é mascarado para não
   competir pela mesma variável.

3. **Podman rootless** (`playbooks/podman.yml`, tag `podman`) — instala
   o Podman via pacman. O pacote `podman` do Arch já resolve
   praticamente toda a base necessária para rootless funcionar de cara,
   como dependência obrigatória (conferido em `pacman -Si podman`/`-Sp
   containers-common` antes de escrever o playbook): `passt` (rede
   rootless padrão do Podman 5+), `containers-common` → `netavark` +
   `aardvark-dns` (rede em modo bridge) e um
   `registries.conf.d/00-shortnames.conf` já mapeando nomes curtos
   comuns de distro (`ubuntu`, `debian`, `fedora`, `archlinux`,
   `tumbleweed`...) para o registry completo — o suficiente para o
   Distrobox puxar imagens sem nenhuma configuração extra de
   `unqualified-search-registries`, então este playbook não mexe em
   `/etc/containers/registries.conf`. O que de fato precisa de atenção
   manual: uma faixa subuid/subgid para o usuário (o `useradd` do Arch
   já aloca uma para contas normais, mas o playbook garante uma —
   sem sobrescrever uma já existente — para contas que não passaram por
   esse fluxo), e uma checagem final (`podman info`) confirmando que o
   rootless está mesmo ativo. cgroups v2 delegation e
   `kernel.unprivileged_userns_clone` já vêm habilitados por padrão no
   Arch/Omarchy atual — nada a fazer aí.

   **Fora do escopo, de propósito**: `loginctl enable-linger` (mantém
   containers rootless rodando sem sessão ativa) não é ligado
   automaticamente — é uma escolha de política que cabe a quem for
   rodar containers como serviços de longa duração, não uma
   pré-condição para rootless funcionar interativamente.
4. **Distrobox** (`playbooks/distrobox.yml`, tag `distrobox`) — instala
   o distrobox via pacman. Depende do Podman (playbook anterior);
   `site.yml` importa os dois nessa ordem, então rodar sem
   `--tags`/`--skip-tags` já garante a sequência certa sozinho — mas
   como este playbook também pode ser rodado isolado
   (`--tags distrobox`), ele falha cedo com orientação se não encontrar
   o Podman, em vez de deixar o pacman instalar o distrobox e só
   descobrir o problema no primeiro `distrobox create`. Nada além do
   pacote é instalado: cada container/distro é criado sob demanda pelo
   próprio usuário, não faz sentido este playbook decidir isso por ele.
5. **libfprint (goodix538d)** (`playbooks/libfprint.yml`, tag
   `libfprint`) — compila e instala em `/usr/local` o fork
   [lbssousa/libfprint](https://github.com/lbssousa/libfprint) (driver
   `goodixtls53xd`, leitor Goodix 27c6:538d), seguindo o modelo do
   repositório irmão
   [lbssousa/bluefin-distrobox-libfprint](https://github.com/lbssousa/bluefin-distrobox-libfprint)
   (Fedora Atomic), mas simplificado agora que `/usr` é gravável e o
   host é Arch, não um sistema imutável — sem Homebrew (o `opencv`
   vira só mais um pacote pacman) e sem relabeling de SELinux (Arch não
   tem). Ainda assim, a pedido, **builda num container distrobox**
   (`libfprint-build`, imagem `archlinux`) em vez de instalar o
   toolchain de build (meson, gcc, headers de desenvolvimento) no host:
   isso continua fazendo sentido fora de um sistema imutável, só que
   por um motivo diferente — manter esses pacotes só-de-build isolados
   e descartáveis (`just libfprint-destroy-container`), sem poluir o
   sistema principal. Confirmado nesta máquina que o distrobox **não**
   compartilha `/usr` do host com o container (só `$HOME`) — por isso o
   playbook ainda faz o *stage* da instalação (`DESTDIR=...`) e copia
   para o host manualmente, e ainda usa um drop-in do
   `fprintd.service` com `LD_LIBRARY_PATH=/usr/local/lib` (o pacote
   oficial `fprintd` já traz o `libfprint` oficial como dependência,
   mesmo soname, sem o driver — o `LD_LIBRARY_PATH` garante prioridade
   para a build em `/usr/local` só para o `fprintd`, sem mudar a
   resolução de bibliotecas do sistema inteiro).

   **Achado testando de verdade** (não estava no bluefin original): o
   `meson.build` do fork pede um pacote pkg-config chamado `opencv4`
   (série 4.x) — nome que o Arch não tem mais (o pacote oficial
   `opencv` já é a série 5.x, `opencv5`; a série 4.x só existe no AUR,
   com ~50 dependências de build incluindo Java/Qt6/VTK, só para
   satisfazer esse nome). Testado e confirmado: a API que o matcher
   SIGFM realmente usa (core, imgproc, imgcodecs, features2d/flann)
   compila sem alterações contra o `opencv5` do Arch — só o nome do
   pacote pkg-config (e da lib `features2d`, que virou `features`)
   mudaram. O playbook cria um `.pc` *shim* redirecionando `opencv4`
   para o `opencv5` real, linkando só os módulos que o libfprint
   realmente usa — não os ~60 do `opencv5.pc` genérico, dos quais
   alguns (`cvv`/`viz`/`hdf`) têm símbolos quebrados nesta instalação
   do Arch (dependem de Qt6/VTK/HDF5 incompletos) e derrubavam a
   geração do GIR/typelib se entrassem no link. O shim não é instalado
   no sistema, só referenciado via `PKG_CONFIG_PATH` durante o build.

   Build validado de ponta a ponta nesta máquina (menos as etapas
   privilegiadas finais, que pedem senha de sudo interativa): as 154
   targets do meson compilam limpo, `ldd` resolve tudo, e
   `fprint-list-supported-devices` lista `27c6:538d` entre os
   dispositivos suportados.

Mais automações devem ser adicionadas a este repositório com o tempo.

## Pré-requisitos

- Um desktop [Omarchy](https://omarchy.org/) (ou qualquer Arch Linux
  com pacman, `locale-gen`/`localectl`, systemd e `xdg-user-dirs`
  disponíveis — nenhuma automação aqui é específica do Hyprland em si).
  O playbook do Bitwarden também espera `git`, `fakeroot` e `makepkg`
  (pacote `pacman`) disponíveis — nenhum AUR helper (`yay`/`paru`) é
  necessário, o playbook builda o AUR sozinho. `git` e `fakeroot` são
  padrão em qualquer instalação do Omarchy (`omarchy-base.packages`).
- O playbook do libfprint precisa do Podman + Distrobox já configurados
  (`--tags podman,distrobox` antes, ou simplesmente rode `just setup`
  sem filtrar tags — `site.yml` já garante essa ordem).
- `sudo` com senha interativa (`locale.gen`, `locale.conf` e a
  instalação/remoção de pacotes via pacman pedem confirmação).

Nem `just` nem `ansible` precisam estar pré-instalados: `./bootstrap.sh`
instala o `just` via pacman se faltar (o único pré-requisito para
conseguir rodar as receitas do Justfile — sem ele não dá nem para
chegar até elas); a partir daí, `just setup` instala o `ansible`
sozinho, junto da collection `community.general` (que fornece o módulo
de pacman usado aqui).

## Uso

```bash
git clone https://github.com/lbssousa/omarchy-setup.git
cd omarchy-setup
./bootstrap.sh   # instala o `just`, se ainda não tiver — só precisa rodar uma vez
just setup
```

Ou diretamente com Ansible:

```bash
sudo pacman -S --needed ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --ask-become-pass
```

Para rodar só uma automação:

```bash
just ptbr       # localização pt-BR
just bitwarden  # Bitwarden
just podman     # Podman rootless
just distrobox  # Distrobox (depende do Podman)
just libfprint  # libfprint goodix538d (depende do Podman + Distrobox)
# ou: ansible-playbook site.yml --ask-become-pass --tags <ptbr|bitwarden|podman|distrobox|libfprint>
```

O playbook é idempotente — rodar de novo é seguro e só aplica o que
ainda não estiver no estado desejado.

## Estrutura

| Arquivo/Diretório          | Papel                                                              |
|-----------------------------|---------------------------------------------------------------------|
| `bootstrap.sh`              | Instala o `just` via pacman, se faltar (rode uma vez, antes de tudo) |
| `site.yml`                  | Índice: importa cada `playbooks/*.yml` com sua tag                 |
| `playbooks/ptbr.yml`        | Localização pt-BR — locale, pastas pessoais, Firefox (tag `ptbr`)  |
| `playbooks/bitwarden.yml`   | Bitwarden — AUR `bitwarden-bin` ou oficial, conforme a versão (tag `bitwarden`) |
| `playbooks/podman.yml`      | Podman rootless (tag `podman`)                                     |
| `playbooks/distrobox.yml`   | Distrobox — depende do Podman (tag `distrobox`)                    |
| `playbooks/libfprint.yml`   | libfprint goodix538d — build em container + instalação em /usr/local (tag `libfprint`) |
| `playbooks/files/`          | Arquivos estáticos copiados como estão (unidades systemd, environment.d, distrobox.ini, shim de pkg-config) — compartilhado pelos playbooks acima |
| `group_vars/all/main.yml`   | Variáveis públicas de todas as automações                          |
| `requirements.yml`          | Collections Ansible necessárias (`community.general`)              |
| `Justfile`                  | Atalhos (`just setup`, `just ptbr`, `just bitwarden`, `just podman`, `just distrobox`, `just libfprint`) |

## Créditos

- Nomes traduzidos oficiais das pastas pessoais em pt_BR: projeto
  [xdg-user-dirs](https://www.freedesktop.org/wiki/Software/xdg-user-dirs/)
  (freedesktop.org).
- Comparação de versões oficial × AUR do Bitwarden via `vercmp`
  (pacman) e a [AUR RPC interface](https://aur.archlinux.org/rpc/) do
  Arch User Repository.
- Configuração do agente SSH do Bitwarden (environment.d + unidades
  systemd --user + máscara do gcr-ssh-agent) importada de
  [lbssousa/bluefin-initial-setup](https://github.com/lbssousa/bluefin-initial-setup),
  com o caminho do socket adaptado para instalação nativa conforme a
  [documentação oficial](https://bitwarden.com/help/ssh-agent/).
- Estrutura do repositório (playbooks modulares, tags, `site.yml`
  como índice) espelhada de
  [lbssousa/bluefin-initial-setup](https://github.com/lbssousa/bluefin-initial-setup).
- Processo de build do libfprint (goodix538d) e a estratégia de
  container de build espelhados de
  [lbssousa/bluefin-distrobox-libfprint](https://github.com/lbssousa/bluefin-distrobox-libfprint),
  adaptados para uma instalação nativa (sem Homebrew, sem SELinux) e
  com um shim de compatibilidade opencv4→opencv5 próprio deste
  repositório.
