use v6;
unit class IO::TailFile;

# XXX rakudo caches the existence of a file...
# https://github.com/rakudo/rakudo/blob/nom/src/core/IO/Path.pm#L9
my class File {
    use nqp;
    has $.file;
    method new($file) { self.bless(:$file) }
    method e { nqp::stat($!file, nqp::const::STAT_EXISTS) == 1 }
    method s { nqp::stat($!file, nqp::const::STAT_FILESIZE) }
    method IO { $!file.IO }
    method open(|c) { self.IO.open(|c) }
    method dirname { self.IO.dirname }
    method watch { self.IO.watch }
    method Str { $!file }
}

my class Impl {
    has File $.file is required;
    has IO::Path $.dir = $!file.dirname.IO;
    has $.size = 0;
    has $.io;
    has buf8 $.buf .= new;
    has $.tap;

    method reset() {
        $!size  = 0;
        $!io.close if $!io;
        $!io = Nil;
        $!tap.close if $!tap;
        $!tap = Nil;
    }
    method Supply(Bool :$bin = False) {
        my &handler = sub ($supplier, $event?) {
            return if $event and $event.event ~~ FileRenamed;
            return unless $!file.e;
            my $current-size = $!file.s;
            return if $!size == $current-size;
            $!io //= try $!file.open(:r);
            return unless $!io;
            my $buf = $!io.read(2048);
            $!size += $buf.elems;
            $!buf ~= $buf;
            my @i = (^$!buf.elems).grep({$!buf[$_] == 0x0a});
            return unless @i;
            for (-1, |@i) Z @i -> ($i, $j) {
                my $line = $.buf.subbuf($i + 1, $j - $i);
                my $out = $bin ?? $line !! $line.decode;
                $supplier.emit($out);
            }
            $!buf = $!buf.subbuf(@i[*-1]);
        };

        my $supplier = Supplier.new;
        $!tap = $!file.watch.tap: -> $event { &handler($supplier, $event) };
        $!dir.watch.tap: -> $event {
            if $event.path eq $!file and $event.event ~~ FileRenamed and $!file.e {
                self.reset;
                $!tap = $!file.watch.tap: -> $event { &handler($supplier, $event) };
            }
        };
        $supplier.Supply;
    }
}

method new(|) { die "call watch() method instead" }

method watch(::?CLASS:U: $filename, Bool :$bin = False) {
    my $file = File.new($filename.IO.abspath);
    Impl.new(:$file).Supply(:$bin);
}

=begin pod

=head1 NAME

IO::TailFile - emulation of tail -f

=head1 SYNOPSIS

  use IO::TailFile;

  react {
    whenever IO::TailFile.watch("access.log") -> $line {
      say $line;
    };
  };

=head1 DESCRIPTION

IO::TailFile is a emulation of C<tail -f>.

=head1 AUTHOR

Shoichi Kaji <skaji@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
