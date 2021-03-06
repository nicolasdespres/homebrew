require 'formula'

class GitManuals < Formula
  url 'http://git-core.googlecode.com/files/git-manpages-1.7.12.2.tar.gz'
  sha1 '8cf6fd255e83226b4abcdcd68dcf315c1995fd92'
end

class GitHtmldocs < Formula
  url 'http://git-core.googlecode.com/files/git-htmldocs-1.7.12.2.tar.gz'
  sha1 '5722156394c7478b2339a1d87aa894bc4d2f5d6b'
end

class Git < Formula
  homepage 'http://git-scm.com'
  url 'http://git-core.googlecode.com/files/git-1.7.12.2.tar.gz'
  sha1 '277b759139ddb62c6935da37de8a483e2c234a97'

  head 'https://github.com/git/git.git'

  depends_on 'pcre' if build.include? 'with-pcre'

  if build.include? 'build-doc'
    depends_on 'asciidoc'
    depends_on 'xmlto'
  end

  option 'with-blk-sha1', 'Compile with the block-optimized SHA1 implementation'
  option 'with-pcre', 'Compile with the PCRE library'
  option 'build-doc', 'Build documentation'

  def install
    # If these things are installed, tell Git build system to not use them
    ENV['NO_FINK'] = '1'
    ENV['NO_DARWIN_PORTS'] = '1'
    ENV['V'] = '1' # build verbosely
    ENV['NO_R_TO_GCC_LINKER'] = '1' # pass arguments to LD correctly
    ENV['NO_GETTEXT'] = '1'
    ENV['PERL_PATH'] = which 'perl' # workaround for users of perlbrew
    ENV['PYTHON_PATH'] = which 'python' # python can be brewed or unbrewed

    # Clean XCode 4.x installs don't include Perl MakeMaker
    ENV['NO_PERL_MAKEMAKER'] = '1' if MacOS.version >= :lion

    ENV['BLK_SHA1'] = '1' if build.include? 'with-blk-sha1'

    if build.include? 'with-pcre'
      ENV['USE_LIBPCRE'] = '1'
      ENV['LIBPCREDIR'] = HOMEBREW_PREFIX
    end


    if build.include? 'build-doc'
      ENV.deparallelize
      args = [ 'all', 'doc', 'install', 'install-doc' ]
    else
      args = [ 'install' ]
    end
    system "make", "prefix=#{prefix}",
                   "CC=#{ENV.cc}",
                   "CFLAGS=#{ENV.cflags}",
                   "LDFLAGS=#{ENV.ldflags}",
                   *args

    # Install the OS X keychain credential helper
    cd 'contrib/credential/osxkeychain' do
      system "make", "CC=#{ENV.cc}",
                     "CFLAGS=#{ENV.cflags}",
                     "LDFLAGS=#{ENV.ldflags}"
      bin.install 'git-credential-osxkeychain'
      system "make", "clean"
    end

    # Install git-subtree
    cd 'contrib/subtree' do
      system "make", "CC=#{ENV.cc}",
                     "CFLAGS=#{ENV.cflags}",
                     "LDFLAGS=#{ENV.ldflags}"
      bin.install 'git-subtree'
    end

    # install the completion script first because it is inside 'contrib'
    (prefix+'etc/bash_completion.d').install 'contrib/completion/git-completion.bash'
    (prefix+'etc/bash_completion.d').install 'contrib/completion/git-prompt.sh'
    (share+'git-core').install 'contrib'

    unless build.include? 'build-doc'
      # We could build the manpages ourselves, but the build process depends
      # on many other packages, and is somewhat crazy, this way is easier.
      GitManuals.new.brew { man.install Dir['*'] }
      GitHtmldocs.new.brew { (share+'doc/git-doc').install Dir['*'] }
    end
  end

  def caveats; <<-EOS.undent
    The OS X keychain credential helper has been installed to:
      #{HOMEBREW_PREFIX}/bin/git-credential-osxkeychain

    The 'contrib' directory has been installed to:
      #{HOMEBREW_PREFIX}/share/git-core/contrib
    EOS
  end

  def test
    HOMEBREW_REPOSITORY.cd do
      `#{bin}/git ls-files -- bin`.chomp == 'bin/brew'
    end
  end
end
