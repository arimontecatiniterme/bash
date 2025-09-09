# Enable the subsequent settings only in interactive sessions
case $- in
  *i*) ;;
    *) return;;
esac


# Configurazione History
export HISTSIZE=10000
# numero massimo di comandi mantenuti nella history in memoria (per la sessione corrente)

export HISTFILESIZE=20000
# numero massimo di comandi salvati nel file ~/.bash_history

export HISTCONTROL=ignoredups:erasedups
# - ignoredups  → non aggiunge in history comandi duplicati consecutivi
# - erasedups   → se il comando è già in history, rimuove la versione precedente e lo sposta in fondo

shopt -s histappend
# fa sì che i comandi vengano aggiunti in coda a ~/.bash_history invece di sovrascriverlo

export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"
# - history -a → aggiunge i nuovi comandi al file history (~/.bash_history)
# - history -c → svuota la history in memoria
# - history -r → ricarica la history da file
# Risultato: mantiene sincronizzata history tra più sessioni aperte

export HISTTIMEFORMAT='%F %T  '
# aggiunge timestamp (YYYY-MM-DD HH:MM:SS) ai comandi quando li visualizzi con 'history'

export BASH_COMMENTS_FILE="$HOME/.bash_comments" 
touch "$BASH_COMMENTS_FILE"




# ===== FZF FUZZY FINDER =====
# Se esistono i file di integrazione di fzf, vengono caricati:
[ -f /usr/share/fzf/key-bindings.bash ] && source /usr/share/fzf/key-bindings.bash
# - key-bindings.bash → aggiunge scorciatoie da tastiera per usare fzf
	
[ -f /usr/share/fzf/completion.bash ] && source /usr/share/fzf/completion.bash
# - completion.bash   → aggiunge autocompletamento avanzato con fzf

# Configurazione FZF
export FZF_DEFAULT_OPTS='
--height 40%
--layout=reverse 
--border
--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9
--color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9
--color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6
--color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4
--prompt=" History > "
--header="↑↓: Naviga | ENTER: Esegue"
--preview="echo {}" 
--preview-window=up:1:hidden:wrap'


#nuova funzione di gestione history
fzf_history() {
    local hist_file="${1:-$HOME/.bash_history}"  					# Se viene passato un file come argomento, lo usa, altrimenti default ~/.bash_history
    local selection key cmd ts                     					# Variabili locali per salvare la selezione, il tasto premuto, il comando e il timestamp

    while true; do                                					# Loop infinito: continuerà a mostrare fzf finché non premi ESC o ENTER
        # fzf con --expect per catturare Ctrl+Q ed ESC
        mapfile -t fzf_output < <(
            awk '
                /^#[0-9]+$/ {                        					# Se la riga inizia con # e numeri → è un timestamp
                    if (ts) {                        					# Se esiste un blocco precedente, stampalo
                        printf "%s %s", strftime("%Y-%m-%d %H:%M:%S", ts), cmd   	# Converte il timestamp in data leggibile + comando
                        if (comment) printf " #%s", substr(comment, 2)           	# Se esiste un commento, aggiungilo preceduto da #
                        printf "\n"
                    }
                    ts = substr($0, 2)               					# Salva il nuovo timestamp senza #
                    cmd = ""                         					# Resetta il comando del nuovo blocco
                    comment = ""                     					# Resetta il commento
                    next
                }
                /^@/ { comment = $0; next }           					# Se la riga inizia con @ → commento, salvalo
                { cmd = $0 }                           					# Altrimenti la riga è il comando
                END {                                  					# Alla fine del file, stampa l’ultimo blocco
                    if (ts) {
                        printf "%s %s", strftime("%Y-%m-%d %H:%M:%S", ts), cmd
                        if (comment) printf " #%s", substr(comment, 2)
                        printf "\n"
                    }
                }
            ' "$hist_file" | tac |							# il comando tac ordina la contrario
            fzf --expect=ctrl-q,ctrl-d,esc --prompt="History > " \
                --header="↑↓ naviga | ENTER: incolla | Ctrl+Q: commento | CTRL+D: cancella un comando | ESC: esci"  
        )

        [[ ${#fzf_output[@]} -eq 0 ]] && break        					# Se non c’è selezione (es. ESC) → esci dal loop

        key="${fzf_output[0]}"                        					# La prima riga dell’output fzf è il tasto premuto
        selection="${fzf_output[-1]}"                 					# L’ultima riga è la selezione effettiva

        [[ "$key" == "esc" ]] && break                					# Se il tasto premuto è ESC → esci subito

        # Ottieni il comando rimuovendo timestamp e commento
        cmd=$(echo "$selection" | sed -E 's/^[0-9-]{10} [0-9:]{8} //; s/ #[^#]*$//')

        # Trova timestamp del comando selezionato
        ts=$(awk -v cmd="$cmd" '
            BEGIN{ts=""}
            /^#[0-9]+$/ { ts_val=substr($0,2); next }   				# Salva il timestamp corrente
            $0==cmd {print ts_val; exit}               					# Se la riga è uguale al comando selezionato → stampa il timestamp
        ' "$hist_file")

        [[ -z "$ts" ]] && { echo "✗ Timestamp non trovato"; continue; } 		# Se non trova timestamp → continua il loop

        if [[ "$key" == "ctrl-q" ]]; then
            stty sane                                  					# Ripristina terminale in modalità normale prima di leggere input
            add_history_comment_by_ts "$ts" "$hist_file"   				# Richiama la funzione per aggiungere/modificare commento

	elif [[ "$key" == "ctrl-d" ]]; then
	    echo "eeeeeeeeeeeeeeeeeee"
            stty sane
            delete_history_block "$ts" "$hist_file"   					# Richiama la funzione delete_history_block
            		            							# Non break → continua il loop, puoi selezionare altri comandi
        else
            # ENTER → copia comando nel prompt e termina
            READLINE_LINE="$cmd"                       	 				# Imposta il comando nella linea di Bash
            READLINE_POINT=${#READLINE_LINE}           					# Posiziona il cursore alla fine
            break                                       				# Esci dal loop dopo ENTER
        fi
    done
}


# Mappa la funzione su Ctrl+R
bind -x '"\C-r": fzf_history'



# funzione di commento
add_history_comment_by_ts() {
    local hist_file="${2:-$HOME/.bash_history}"
    local ts="$1"
    local cmd comment new_comment temp_file

    [[ -z "$ts" ]] && { echo "✗ Devi fornire un timestamp"; return 1; }

    # Trova il comando corrispondente al timestamp
    cmd=$(awk -v ts="$ts" '
        BEGIN{cmd=""}
        /^#[0-9]+$/ { if(substr($0,2)==ts) {found=1; next} else {found=0} }
        { if(found) { print; exit } }
    ' "$hist_file")

    [[ -z "$cmd" ]] && { echo "✗ Timestamp non trovato"; return 1; }

    # Leggi commento esistente (se presente)
    comment=$(awk -v ts="$ts" '
        BEGIN{found=0}
        /^#[0-9]+$/ { if(substr($0,2)==ts){found=1} else {found=0} next }
        /^@/ { if(found){ print substr($0,2); exit } }
    ' "$hist_file")

    echo "Comando selezionato: $cmd"
    [[ -n "$comment" ]] && echo "Commento attuale: $comment"

    # Chiedi nuovo commento
    read -p "Nuovo commento: " new_comment
    [[ -z "$new_comment" ]] && { echo "✗ Nessun commento inserito"; return 1; }

    temp_file="${hist_file}.tmp.$$"

    if [[ -n "$comment" ]]; then
        # Modifica commento esistente
        awk -v ts="$ts" -v new="@${new_comment}" '
            BEGIN{found=0}
            /^#[0-9]+$/ { if(substr($0,2)==ts) found=1; else found=0 }
            { if(found && /^@/) {print new; next} print $0 }
        ' "$hist_file" > "$temp_file"
    else
        # Aggiungi commento subito dopo il comando
        awk -v ts="$ts" -v cmd="$cmd" -v new="@${new_comment}" '
            BEGIN{found=0}
            /^#[0-9]+$/ { if(substr($0,2)==ts){found=1} else {found=0} }
            { print $0; if(found && $0==cmd){ print new; found=0 } }
        ' "$hist_file" > "$temp_file"
    fi

    mv -f "$temp_file" "$hist_file"
    echo "✓ Commento salvato correttamente"
}



# cancella un comando ed eventuale commento associato ad un particolare timestamp
delete_history_block() {
    local ts="$1"                             # Il primo parametro della funzione è il timestamp
    local hist_file="${2:-$HOME/.bash_history}" # File di history (default ~/.bash_history)
    local temp_file

    # Controlla che il timestamp sia passato
    [[ -z "$ts" ]] && { echo "✗ Devi fornire un timestamp"; return 1; }

    # Verifica che il timestamp esista nel file
    if ! grep -q "^#$ts$" "$hist_file"; then
        echo "✗ Timestamp $ts non trovato in $hist_file"
        return 1
    fi

    temp_file="${hist_file}.tmp.$$"

    # Usa awk per eliminare il blocco con il timestamp specificato
    awk -v ts="$ts" '
        BEGIN {delete_block=0}
        /^#[0-9]+$/ {
            if(substr($0,2)==ts) { delete_block=1; next }  # inizia il blocco da cancellare
            else { delete_block=0 }                         # blocco successivo non da cancellare
        }
        delete_block==0 { print $0 }                        # stampa solo righe non da cancellare
    ' "$hist_file" > "$temp_file"

    # Sovrascrive il file originale
    mv -f "$temp_file" "$hist_file"

    echo "✓ Blocco con timestamp $ts cancellato"
}






# Path to your oh-my-bash installation.
export OSH='/home/andrea/.oh-my-bash'

# Set name of the theme to load. Optionally, if you set this to "random"
# it'll load a random theme each time that oh-my-bash is loaded.
OSH_THEME="lambda"

# If you set OSH_THEME to "random", you can ignore themes you don't like.
# OMB_THEME_RANDOM_IGNORED=("powerbash10k" "wanelo")
# You can also specify the list from which a theme is randomly selected:
OMB_THEME_RANDOM_CANDIDATES=("font" "powerline-light" "minimal")

# Uncomment the following line to use case-sensitive completion.
# OMB_CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion. Case
# sensitive completion must be off. _ and - will be interchangeable.
# OMB_HYPHEN_SENSITIVE="false"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_OSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you don't want the repository to be considered dirty
# if there are untracked files.
# SCM_GIT_DISABLE_UNTRACKED_DIRTY="true"

# Uncomment the following line if you want to completely ignore the presence
# of untracked files in the repository.
# SCM_GIT_IGNORE_UNTRACKED="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.  One of the following values can
# be used to specify the timestamp format.
# * 'mm/dd/yyyy'     # mm/dd/yyyy + time
# * 'dd.mm.yyyy'     # dd.mm.yyyy + time
# * 'yyyy-mm-dd'     # yyyy-mm-dd + time
# * '[mm/dd/yyyy]'   # [mm/dd/yyyy] + [time] with colors
# * '[dd.mm.yyyy]'   # [dd.mm.yyyy] + [time] with colors
# * '[yyyy-mm-dd]'   # [yyyy-mm-dd] + [time] with colors
# If not set, the default value is 'yyyy-mm-dd'.
# HIST_STAMPS='yyyy-mm-dd'

# Uncomment the following line if you do not want OMB to overwrite the existing
# aliases by the default OMB aliases defined in lib/*.sh
# OMB_DEFAULT_ALIASES="check"

# Would you like to use another custom folder than $OSH/custom?
# OSH_CUSTOM=/path/to/new-custom-folder

# To disable the uses of "sudo" by oh-my-bash, please set "false" to
# this variable.  The default behavior for the empty value is "true".
OMB_USE_SUDO=true

# To enable/disable display of Python virtualenv and condaenv
# OMB_PROMPT_SHOW_PYTHON_VENV=true  # enable
# OMB_PROMPT_SHOW_PYTHON_VENV=false # disable

# To enable/disable Spack environment information
# OMB_PROMPT_SHOW_SPACK_ENV=true  # enable
# OMB_PROMPT_SHOW_SPACK_ENV=false # disable

# Which completions would you like to load? (completions can be found in ~/.oh-my-bash/completions/*)
# Custom completions may be added to ~/.oh-my-bash/custom/completions/
# Example format: completions=(ssh git bundler gem pip pip3)
# Add wisely, as too many completions slow down shell startup.
completions=(
  git
  composer
  ssh
)

# Which aliases would you like to load? (aliases can be found in ~/.oh-my-bash/aliases/*)
# Custom aliases may be added to ~/.oh-my-bash/custom/aliases/
# Example format: aliases=(vagrant composer git-avh)
# Add wisely, as too many aliases slow down shell startup.
aliases=(
  general
)

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-bash/plugins/*)
# Custom plugins may be added to ~/.oh-my-bash/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  bashmarks
)

# Which plugins would you like to conditionally load? (plugins can be found in ~/.oh-my-bash/plugins/*)
# Custom plugins may be added to ~/.oh-my-bash/custom/plugins/
# Example format:
#  if [ "$DISPLAY" ] || [ "$SSH" ]; then
#      plugins+=(tmux-autoattach)
#  fi

# If you want to reduce the initialization cost of the "tput" command to
# initialize color escape sequences, you can uncomment the following setting.
# This disables the use of the "tput" command, and the escape sequences are
# initialized to be the ANSI version:
#
#OMB_TERM_USE_TPUT=no

source "$OSH"/oh-my-bash.sh

# User configuration
# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/rsa_id"

# Set personal aliases, overriding those provided by oh-my-bash libs,
# plugins, and themes. Aliases can be placed here, though oh-my-bash
# users are encouraged to define aliases within the OSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias bashconfig="mate ~/.bashrc"
# alias ohmybash="mate ~/.oh-my-bash"
