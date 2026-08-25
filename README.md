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
     Documentos, Música, Imagens, Vídeos), só para as pastas que já
     estiverem habilitadas — se Área de Trabalho/Modelos/Público
     estiverem desabilitadas (`XDG_*_DIR="$HOME/"`, como costuma ser
     preferência pessoal), permanecem desabilitadas. O comando
     `xdg-user-dirs-update`, sozinho, **nunca** renomeia pastas já
     existentes — ele só cria as que ainda não têm entrada em
     `user-dirs.dirs`; quem faz esse rename (com diálogo de
     confirmação) é o `xdg-user-dirs-gtk-update`, uma ferramenta
     gráfica que não dá para rodar de forma não interativa. Este
     playbook replica manualmente o mesmo mecanismo (`mv` +
     `xdg-user-dirs-update --set`), sem diálogo, mas com a mesma
     garantia de segurança: só renomeia se a pasta de origem existir e
     a de destino ainda não existir — idempotente, seguro rodar de
     novo. `XDG_PROJECTS_DIR` (entrada extra do Omarchy em
     `/etc/xdg/user-dirs.defaults`, fora do padrão do xdg-user-dirs)
     fica de fora do escopo, por não ser um dos 8 nomes canônicos
     aceitos por `--set`.
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

Mais automações devem ser adicionadas a este repositório com o tempo.

## Pré-requisitos

- Um desktop [Omarchy](https://omarchy.org/) (ou qualquer Arch Linux
  com pacman, `locale-gen`/`localectl`, systemd e `xdg-user-dirs`
  disponíveis — nenhuma automação aqui é específica do Hyprland em si).
  O playbook do Bitwarden também espera `git`, `fakeroot` e `makepkg`
  (pacote `pacman`) disponíveis — nenhum AUR helper (`yay`/`paru`) é
  necessário, o playbook builda o AUR sozinho. `git` e `fakeroot` são
  padrão em qualquer instalação do Omarchy (`omarchy-base.packages`).
- `sudo` com senha interativa (`locale.gen`, `locale.conf` e a
  instalação/remoção de pacotes via pacman pedem confirmação).

`ansible` **não** precisa estar pré-instalado: `just setup` instala via
pacman automaticamente se faltar, junto da collection
`community.general` (que fornece o módulo de pacman usado aqui).

## Uso

```bash
git clone https://github.com/lbssousa/omarchy-setup.git
cd omarchy-setup
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
# ou: ansible-playbook site.yml --ask-become-pass --tags <ptbr|bitwarden>
```

O playbook é idempotente — rodar de novo é seguro e só aplica o que
ainda não estiver no estado desejado.

## Estrutura

| Arquivo/Diretório          | Papel                                                              |
|-----------------------------|---------------------------------------------------------------------|
| `site.yml`                  | Índice: importa cada `playbooks/*.yml` com sua tag                 |
| `playbooks/ptbr.yml`        | Localização pt-BR — locale, pastas pessoais, Firefox (tag `ptbr`)  |
| `playbooks/bitwarden.yml`   | Bitwarden — AUR `bitwarden-bin` ou oficial, conforme a versão (tag `bitwarden`) |
| `group_vars/all/main.yml`   | Variáveis públicas de todas as automações                          |
| `requirements.yml`          | Collections Ansible necessárias (`community.general`)              |
| `Justfile`                  | Atalhos (`just setup`, `just ptbr`, `just bitwarden`)               |

## Créditos

- Nomes traduzidos oficiais das pastas pessoais em pt_BR: projeto
  [xdg-user-dirs](https://www.freedesktop.org/wiki/Software/xdg-user-dirs/)
  (freedesktop.org).
- Comparação de versões oficial × AUR do Bitwarden via `vercmp`
  (pacman) e a [AUR RPC interface](https://aur.archlinux.org/rpc/) do
  Arch User Repository.
- Estrutura do repositório (playbooks modulares, tags, `site.yml`
  como índice) espelhada de
  [lbssousa/bluefin-initial-setup](https://github.com/lbssousa/bluefin-initial-setup).
