# This external command dump a shell script that will re-install all your
# installed formulae.  It is useful if you want to re-install all your formulae
# after a full system restoration, or when you change your compiler, or Xcode
# upgrade, etc...  All your installation options are preserved and formulae
# are installed in topological order to ensure another formula will not
# installed another one without your favorite options.
#
# The shell script does a little more thought, since it provides you some
# options and tracks which formula installation has failed. See the usage
# message for further information.
#
# Example:
# $ brew dump > brew-reinstall
# $ for i in $(brew list); do brew rm --force $i; done
# $ /bin/sh brew-reinstall --force
#
# Please report any problem to <nicolas.despres@gmail.com>

# Re-install shell script template.
TEMPLATE = %q{#!/bin/sh
# ==============================================================================
# Generated by 'brew dump' version <%= HOMEBREW_VERSION %> DO NOT EDIT!!!
# ==============================================================================

set -e
set -u
export LC_ALL=C

VERBOSE='no'
FAILED_INSTALL_LIST=''
DRY_RUN='no'
ME=${0##*/}

usage()
{
  cat <<EOF
Usage: $ME [options]

Options:
  --dry-run     Do not actually install anything, just show what would be done.
  --force       Actually do the installation (incompatible with --dry-run).
  --verbose     Pass --verbose option to 'brew install'.

Generated by 'brew dump' version <%= HOMEBREW_VERSION %>.
EOF
}

fatal()
{
  for i in
  do
    echo >&2 "$ME: fatal: $i"
  done
  exit 1
}

run()
{
  if test x"$DRY_RUN" = xyes
  then
    echo "$ME: run: $@"
  else
    "$@"
  fi
}

brew_install_run()
{
  if test x"$VERBOSE" = xno
  then
    run brew install "$@"
  else
    run brew install --verbose "$@"
  fi
}

brew_install()
{
  local name="$1"; shift
  local options="$@"
  # Do not quote $options because it may be empty and we don't want an empty
  # argument in this case.
  if ! brew_install_run $options "$name"
  then
    FAILED_INSTALL_LIST="$FAILED_INSTALL_LIST $name"
  fi
}

# Get the options.
get_options()
{
  if test $# -eq 0 -o $# -gt 1
  then
    usage
    exit 1
  else
    local i
    for i in "$@"
    do
      case "$i" in
        --dry-run) DRY_RUN='yes';;
        --force) DRY_RUN='no';;
        --verbose) VERBOSE='yes';;
        *) fatal "unknown option '$i'";;
      esac
    done
  fi
}

get_options "$@"

# Entry point.
cat <<EOF
================================================================================
Start re-installing all your formula...
================================================================================
EOF

# Install all formulae.
<% COMMANDS.each do |cmd| -%>
<%= cmd %>
<% end -%>

<% unless UNAVAILABLE_FORMULAE.empty? -%>
# Warn about unavailable formulae.
cat <<EOF
================================================================================
Warning:
 Some formula have not been re-installed because we failed to load it.  This
 is probably due to a bug in Homebrew or because you have not installed a
 formula using the proper way.

Here the list:
<% UNAVAILABLE_FORMULAE.each do |f| -%>
<%= "  " + f %>
<% end -%>
EOF
<% end -%>

# Print the list of formulae that failed to install.
if test x"$FAILED_INSTALL_LIST" != x
then
  cat <<EOF
================================================================================
Error: Some formula installation failed.

Here the list:
EOF
  for i in "$FAILED_INSTALL_LIST"
  do
    echo "  $i"
  done
fi

cat <<EOF
================================================================================
EOF
}

# ======================== #
# Beginning of the program #
# ======================== #

require 'formula'
require 'tab'
require 'erb'

$STATUS = 0

def error msg
  STDERR.puts "#{Tty.red}Error#{Tty.reset}: #{msg}"
  $STATUS = 1
end

def info msg
  STDERR.puts "#{Tty.yellow}Info#{Tty.reset}: #{msg}"
end

class Command

  def initialize(name, args)
    @name = name
    @args = args
  end

  attr_reader :name, :args

  def to_s
    cmd = "brew_install"
    cmd << " #@name"
    cmd << " " + self.args_s
    cmd
  end

  def args_s
    if @args.empty?
      ""
    else
      @args.join(' ')
    end
  end

end # class Command

# Intended to extend a hash map where the key are the nodes and the value is
# a hash map of this form: { :deps => anArray, :obj => anObject }
# The :obj key can be changed when _topo_sort_ is called. Its value is object
# return in the sorted array.
module TopoSort

  # Work a Hash which is expected to be self.
  def topo_sort(key = :obj)
    result = []
    mark = {} # Visited node
    self.keys.each do |node|
      topo_sort_rec(node, mark, result, key)
    end
    result
  end

  private

  def topo_sort_rec(node, mark, result, key)
    return if mark.has_key? node
    mark[node] = true
    self[node][:deps].each do |succ|
      topo_sort_rec(succ.to_s, mark, result, key)
    end
    result << self[node][key]
  end

end # module TopoSort

# Get the formula of the given _name_ using an ugly hack to get the optional
# dependencies.
# This is a work around these issues:
# https://github.com/mxcl/homebrew/issues/10708
# https://github.com/mxcl/homebrew/issues/10555
# https://github.com/mxcl/homebrew/issues/10050
def get_formula(name)
  # Get the formula.
  f = Formula.factory(name)
  t = Tab.for_formula f
  # Inject the options in ARGV.
  opts = t.used_options
  ARGV.concat(opts)
  # Remove required formula.
  klass_name = Formula.class_s(name)
  Object.send(:remove_const, klass_name)
  # Reload the formula
  load f.path
  klass = Object.const_get(klass_name)
  f = klass.new(name)
  # Remove the options from ARGV.
  ARGV.delete_if{|x| opts.include? x }
  f
end

# Compute the list of command to re-install all the formulae.
INSTALLED = HOMEBREW_CELLAR.children.select{|pn| pn.directory? }.collect{|pn| pn.basename.to_s }
if INSTALLED.empty?
  error "Nothing to dump since no formulae are intalled."
  exit 2
end
UNAVAILABLE_FORMULAE = []
GRAPH = {}
GRAPH.extend TopoSort
INSTALLED.each do |name|
  begin
    f = get_formula(name)
    t = Tab.for_formula f
    options = []
    options << '--build-from-source' unless t.built_bottle
    options += t.used_options
    GRAPH[f.name] = { :cmd => Command.new(f.name, options), :deps => f.deps }
  rescue FormulaUnavailableError => e
    # NOTE(Nicolas Despres): This should never happens since multiple
    # repository support has been added since Homebrew 0.9.  However, I prefer
    # to keep this section just in case.
    error "Cannot find formula #{e.name}."
    UNAVAILABLE_FORMULAE << e.name
  end
end
COMMANDS = GRAPH.topo_sort(:cmd)
if ARGV.verbose?
  COMMANDS.each do |cmd|
    info "#{cmd.name}: #{cmd.args_s}"
  end
end

# Compile and print the script template.
puts ERB.new(TEMPLATE, $SAFE, '%<>-').result

exit $STATUS
