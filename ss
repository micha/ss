#!/usr/bin/env perl

use feature ":5.10";

use Number::Latin;
use Text::CSV::Simple;
use Curses;
use Curses::UI;
use Curses::UI::Widget;
use Curses::UI::Common;
use Data::Dumper;

$ENV{ESCDELAY} = 0;

package Ui;

use Curses;
use Curses::UI;
use Curses::UI::Widget;
use Curses::UI::Common;
use Data::Dumper;
use Number::Latin;
use List::Util qw[min max];

sub new() {
  my $class = shift;
  my $data  = shift;

  my $self  = {};

  my $grid;
  my $binding;
  my $mode  = 0;

  my $cui = new Curses::UI( 
    -clear_on_exit => 1,
    -color_support => 1
  );

  $cui->set_binding(sub {exit}, "\cQ");

  my $w1 = $cui->add('w1', 'Window',
    -height => 1,
    -bg     => 'yellow',
    -fg     => 'black',
  );

  my $w2 = $cui->add(undef, 'Window',
    -y          => 1,
  );

  my $cmd  = $w1->add('command', 'TextEntry');

  $grid = $w2->add('grid', 'Grid',
    -fg         => "white",
    -bg         => "black",
    -onnextpage => sub {
      my $grid = shift;
      $grid->page($grid->page() + 1);
      &update($grid, $data);
      return $grid;
    },
    -onprevpage => sub {
      my $grid = shift;
      my $next = $grid->page() - 1;
      return 0 if ($next < 0);
      $grid->page($next);
      &update($grid, $data);
      return $grid;
    },
    -onrowfocus => sub {
      my $row = shift;
      $row->bg('blue');
      $row->fg('white');
    },
    -onrowblur  => sub {
      my $row = shift;
      $row->bg('');
      $row->fg('');
    },
    -oncellfocus => sub {
      $pp = $grid->page();
      $ps = $grid->page_size();

      $r1 = $grid->{-row_idx} + $pp * $ps;
      $c1 = uc(int2latin($grid->{-cell_idx}));

      $cmd->text("$c1$r1");
      $cmd->draw();
    },
    -basebindings => {
    },
  );

  my %mode = ();

  $mode{normal} = sub {
    my ($cui, $k) = @_;

    given ($k) {
      when ('l') { $grid->next_cell(); }
      when ('h') { $grid->prev_cell() unless $grid->{-cell_idx} == 1; }
      when ('j') { $grid->next_row(); }
      when ('k') { $grid->prev_row(); }
      when ("\cF") { $grid->grid_pagedown(1); }
      when ("\cB") { $grid->grid_pageup(1); }
      when ('>') {
        my $cell = $grid->get_foused_cell();
        $grid->set_cell_width($cell, $cell->{-width} + 5);
        $grid->draw();
      }
      when ('<') {
        my $cell = $grid->get_foused_cell();
        $grid->set_cell_width($cell, max(0, $cell->{-width} - 5));
        $grid->draw();
      }
      when ('=') {
        delete $cui->{-bindings}{""};
        $cui->set_binding(
          sub {
            delete $cui->{-bindings}{KEY_ENTER()};
            $cui->set_binding($mode{normal}, "");
            $grid->get_foused_cell()->cursor_to_home();
          },
          KEY_ENTER()
        );
      }
    }
  };

  sub mouse1() {
    my ($grid, $event, $x, $y) = @_;

    my $row = $grid->row_for_index($y - 1);
    my $cells = $grid->{_cells};
    my $xoffset = 0;
    my $cell;

    for my $i (0 .. $#{$cells}) {
      $cell = $grid->id2cell($cells->[$i]);
      $xoffset += $cell->current_width + 1;
      last if ($x < $xoffset);
    }

    $grid->focus_row($row, undef, 0);
    $grid->focus_cell($cell, undef, 0);

    $cell->cursor_to_home();
    $cell->draw();
  }

  $cui->set_binding($mode{normal}, "");
  $grid->set_mouse_binding(\&mouse1, BUTTON1_CLICKED());

  for my $id(0 .. 255 ) {
    $grid->add_cell("cell".$id,
      -label      => uc(int2latin($id)),
      -align      => $id==0 ? 'R':'L',
      -frozen     => $id==0 ? 1:0,
      -focusable  => $id==0 ? 0:1,
      -width      => $id==0 ? 3:10,
      -readonly	  => $id==0 ? 1:0,
      -overwrite  => 1,
    );
  }

  for my $i (1 .. $grid->page_size()+1) {
    $grid->add_row(undef);
  }

  $self->{data}     = $data;
  $self->{cui}      = $cui;
  $self->{cmd}      = $cmd;
  $self->{grid}     = $grid;
  $self->{sheets}   = $sheets;
  $self->{w0}       = $w0;
  $self->{w1}       = $w1;
  $self->{w2}       = $w2;

  return bless($self, $class);
}

sub update() {
  my $gr = shift;
  my $dd = shift;

  my $pp = $gr->page();
  my $ps = $gr->page_size();

  my $start = $pp * $ps;
  my $end   = $start + $ps - 1;

  for my $i (1 .. $ps) {
    $gr->set_value('row'.$i, 'cell0', $i+$start);
    my @d = @{$dd->[$i+$start]};
    for my $j (0 .. $#d) {
      $gr->set_value('row'.$i, 'cell'.($j+1), $d[$j]);
    }
  }
}

sub start() {
  my $self = shift;

  &update($self->{grid}, $self->{data});
  $self->{grid}->next_cell();
  $self->{grid}->focus();
  $self->{cui}->mainloop();
}

sub alert() {
  my $self = shift;
  my $s    = shift;

  $self->{cmd}->text(sprintf("%-*s", $self->{w2}->width(), $s));
}

sub done() {
  exit;
}

package Io;

use File::Slurp;

sub load_csv() {
  my $file = shift;

  my $parser = Text::CSV::Simple->new;
  @data = $parser->read_file($file);

  return @data;
}

sub load_file($;) {
  my $file = shift;
  
  if ($file =~ /\.csv$/) {
    return &load_csv($file);
  } elsif ($file =~ /\.ss$/) {
    my $VAR1;
    my $src = read_file($file);
    eval $src;
    return @{$VAR1};
  }
}

package Ss;

use Data::Dumper;

my $file = $ARGV[0];

my $ss = Ui->new();
my @data = Io::load_file($file);

$ss->alert($file);
$ss->start(\@data);
