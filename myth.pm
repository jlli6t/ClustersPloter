package myth;
use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(format_scale read_list draw_genes display_conf read_conf default_setting check_track_order check_para get_para);


sub format_scale(){
            my ($last_tick_label)=@_;
            $last_tick_label=reverse($last_tick_label);
			$last_tick_label=~ s/(\d\d\d)/$1,/g;
            $last_tick_label=reverse($last_tick_label);
            return $last_tick_label;
}

sub read_list(){
	###start:get scaffold length in genome file and scaffold length  in gff file
	my %fts;
	my ($list, $conf) = @_;
	my (%genome,%gff,@track_order,$sample_num);
	my @features=split(/,/, $conf->{feature_keywords});
    my $space_len = $conf->{space_between_blocks};# 500bp是默认的blocks之间的间距
	my %uniq_sample;
	open LI,"$list" or die "$!";
	while(<LI>){
		chomp;
		next if($_=~ /^\s*$/||$_=~ /^#/);
		$sample_num++;
		my $block_index=1;
		my %scf_block_id;
		my ($sample,$gffs,$genome,@arrs)=split(/\s+/,$_); # $seq_id,$seq_draw_start,$seq_draw_end
		push @track_order, $sample;

		if(exists $uniq_sample{$sample}){
			die "error:more than one $sample, not allow same 1th column in $list~\n " 
		}else{
			$uniq_sample{$sample}="";
		}
		print "$sample\n";
		if(@arrs%3){
			die "error:$list line $. error format:$_, should be separated by \\t \n"; 
		}
		open GE,"$genome" or die "$!";
		$/=">";<GE>;
		while(<GE>){
			chomp;
			my ($id,$seq)=split(/\n/,$_,2);
			$id=~ /^(\S+)/;
			$id=$1;
			$seq=~ s/\s+//g;
			my $len=length $seq;
			$genome{$sample}{$id}{len}=$len;
		}
		close GE;
		$/="\n";

		my %all_seq_id;
		my @gffss = split(/,/, $gffs);
		my $gene_index;
		foreach my $gffs(@gffss){
			open GFF,"$gffs" or die "canot open $gffs\n";
			while(<GFF>){
				chomp;
				next if($_=~ /^#/||$_=~ /^\s*$/);
				my @arr=split(/\t/,$_);
				die "error: need 9 columns for gff format, $gffs, line$.\n" if(@arr!=9);
				$all_seq_id{$arr[0]} = "";
			}
			close GFF;
			open GFF,"$gffs" or die "$!";
			while(<GFF>){
				chomp;
				next if($_=~ /^#/||$_=~ /^\s*$/);
				my @arr=split(/\t/,$_);
				die "error: $gffs should have tab in file~\n" if(@arr==1);
				my $block_index=-1;
				my $start_f=$arr[3];
				my $end_f=$arr[4];
				#die "die1\n" if($start_f == 5998);
				if($arr[3] > $arr[4]){
					$arr[3] = $end_f;
					$arr[4] = $start_f;
				}
				my $flag=1;
				foreach my $f(@features){
					next if ($f=~ /^\s*$/);
					$f=~ s/\s//g;
					$flag =0 if($arr[2]=~ /$f/);
				}
		        next if($flag);

				if(@arrs){ # has seq_id mean not full length of whole gff
					for (my $arrs_index=0;$arrs_index < scalar(@arrs);$arrs_index+=3){
						my ($seq_id,$seq_draw_start,$seq_draw_end) = @arrs[$arrs_index..$arrs_index+2];
						die "error: $seq_id not in $gffs\n" if(not exists $all_seq_id{$seq_id});
						my $seq_draw_start_tmp=$seq_draw_start;
						my $seq_draw_end_tmp=$seq_draw_end;

						$seq_draw_start = eval($seq_draw_start);
						$seq_draw_end = eval($seq_draw_end);
						die "error:for $seq_id , start $seq_draw_start_tmp should less than end $seq_draw_end_tmp in --list " if($seq_draw_end <= $seq_draw_start);

						#print "$seq_id,$seq_draw_start,$seq_draw_end\n";
						next unless ($arr[0] eq $seq_id && $arr[3] >= $seq_draw_start && $arr[4] <= $seq_draw_end);
						#die "die1\n" if($start_f == 5998);
						$seq_draw_end = ($genome{$sample}{$seq_id}{len}>=$seq_draw_end)? $seq_draw_end:$genome{$sample}{$seq_id}{len}; #防止seq_draw_end越界
						$genome{$sample}{$arr[0]}{$arrs_index}{len}=$seq_draw_end -$seq_draw_start+1; # 一条scaffold有多个block
						$arr[3]=$arr[3]-$seq_draw_start +1;
						$arr[4]=$arr[4]-$seq_draw_start +1;
						$block_index = ($arrs_index/3+1);
						#print "hereis $block_index\n";
						if(not exists  $gff{$sample}{chooselen_single}{$block_index}){
							$gff{$sample}{chooselen_single}{$block_index}{len} = $genome{$sample}{$arr[0]}{$arrs_index}{len};
							$gff{$sample}{chooselen_single}{$block_index}{start} = $seq_draw_start;
							$gff{$sample}{chooselen_single}{$block_index}{end} = $seq_draw_end;
							#gff{$sample}{chooselen_single}{$block_index}{scf_id} = $arr[0];
							$gff{$sample}{chooselen_all} +=$gff{$sample}{chooselen_single}{$block_index}{len}; ## 把每行所有block长度加起来
							$gff{$sample}{chooselen_all} += $space_len ; ## 加上 每个block之间的宽度，500bp相当于一个基因的长度,后面最好把这个500bp改成每个track实际的平均基因长度
                        }
                        my ($gff,$fts);
                        ($conf, $gff, $block_index, $gene_index, $fts) = &go_line($conf, \%gff, $sample, $block_index, $gffs, $., $start_f, $end_f, \@arr, \@arrs, $_, $gene_index, \%fts);
                        %gff=%$gff;
                        %fts=%$fts;

					}

				}else{ # list里面没有定义seq_id/start/end,即要画full-length of scaffold
					#print "not seq_id\n";
                    if(not exists $scf_block_id{$arr[0]}){
                        $block_index++;
                        $scf_block_id{$arr[0]}="";
                    }
                    $block_index=1 if($block_index==0);
					if(not exists  $gff{$sample}{chooselen_single}{$block_index}){
						$gff{$sample}{chooselen_single}{$block_index}{len} = $genome{$sample}{$arr[0]}{len};
						$gff{$sample}{chooselen_single}{$block_index}{start} = 1;
						$gff{$sample}{chooselen_single}{$block_index}{end} = $genome{$sample}{$arr[0]}{len};

						$gff{$sample}{chooselen_all} +=$gff{$sample}{chooselen_single}{$block_index}{len}; # ## 把每行所有block(即scaffold)长度加起来
						#print "$sample	$gff{$sample}{chooselen_all}\n";
						$gff{$sample}{chooselen_all} += $space_len ; ## 这个500最好改成每个track的blocks的平均长度的一定比例，比如一半
					}

                    my ($gff,$fts);
                    ($conf, $gff, $block_index, $gene_index, $fts) = &go_line($conf, \%gff, $sample, $block_index, $gffs, $., $start_f, $end_f, \@arr, \@arrs, $_, $gene_index, \%fts);
                    %gff=%$gff;
                    %fts=%$fts;

				}
    

			}
			close GFF;
		}
	}
	close LI;
	return (\%genome, \%gff, \@track_order, $sample_num, \%fts);
	####end:get scaffold length in genome file and scaffold length  in gff file
}

sub go_line(){
    my ($conf, $gff, $sample, $block_index, $gffs, $line_num, $start_f, $end_f, $arr, $arrs, $line, $gene_index, $fts)=@_;
                my @arr=@{$arr};
                my @arrs=@{$arrs};

				$line=~ /\sID=(\S+)/;
				my $feature_id=$1;
                $feature_id=~ s/\s//g;
                $feature_id=~ s/;.*//g;
				die "error: $feature_id in $gffs should not contain , \n" if($feature_id=~ /,/);
				if(exists $fts->{$feature_id}){
					die "error: feature_id should be uniq, but $feature_id appear more than one time in --list \n\n";
				}else{
					$fts->{$feature_id}{sample} = $sample;
					$fts->{$feature_id}{scf} = $arr[0];
					#print "fts has $feature_id\n";
				}
				$gene_index++;
				if(!$arr[3]){die "error:$gffs line $line_num\n"}
				$gff->{$sample}->{block}->{$block_index}->{$arr[0]}->{$gene_index}->{start}=$arr[3]; # block_index 是指每行中每个cluster的左右顺序
				$gff->{$sample}->{block}->{$block_index}->{$arr[0]}->{$gene_index}->{start_raw}=$start_f; # block_index 是指每行中每个cluster的左右顺序
				$gff->{$sample}->{block}->{$block_index}->{$arr[0]}->{$gene_index}->{end}=$arr[4];
				$gff->{$sample}->{block}->{$block_index}->{$arr[0]}->{$gene_index}->{end_raw}=$end_f;
				$gff->{$sample}->{block}->{$block_index}->{$arr[0]}->{$gene_index}->{id}=$feature_id;
                $gff->{$sample}->{scf}->{$arr[0]}="";
				if(!$feature_id){die "die:line is $line\n"}
				$gff->{$sample}->{block}->{$block_index}->{$arr[0]}->{$gene_index}->{strand}=($arr[6]=~ /\+/)? 1:0;
				$conf->{feature_setting2}->{$feature_id}->{start}=$start_f;
				$conf->{feature_setting2}->{$feature_id}->{end}=$end_f;
				$conf->{feature_setting2}->{$feature_id}->{sample}=$sample;
				$conf->{feature_setting2}->{$feature_id}->{scf_id}=$arr[0];
				$conf->{feature_setting2}->{$feature_id}->{type}=$arr[2];
				die "error: sample $sample should not have : char\n" if($sample=~ /:/);
				die "error: scaffold_id $arr[0] should not have : char\n" if($arr[0]=~ /:/);

    return ($conf, $gff, $block_index, $gene_index, $fts);
}


sub get_para(){
    my ($para, $feature_id, $conf)=@_;
    #print "$para,$feature_id,\n";
    my $ret_para;
    #if($para eq "feature_opacity" && $feature_id eq "gene_s101"){
    #    use Data::Dumper;
    #   print Dumper($conf);
    #}
    if(exists $conf->{feature_setting2}->{$feature_id} && exists $conf->{feature_setting2}->{$feature_id}->{$para}){
        $ret_para = $conf->{feature_setting2}->{$feature_id}->{$para}
    }else{
        $ret_para = $conf->{$para};
    }
    return $ret_para;
}

sub draw_genes(){
	#draw_genes($index_id, $index_start, $index_end, $index_strand, $gene_height_medium, $gene_height_top, $gene_width_arrow, $shift_x, $top_distance, $sample_single_height, $sample, $scf[0], $index_color,  $index_label_content, $index_label_size, $index_label_col, $index_label_position, $index_label_angle, $angle_flag); 		## draw_gene 函数需要重写，输入起点的xy坐标，正负链等信息即可
	my ($feature_id,$start,$end,$strand,$start_raw,$end_raw,$gene_height_medium,$gene_height_top,$gene_width_arrow,$shift_x,$shift_y,$feature_shift_y,$sample_single_height,$sample,$id, $index_color, $index_label_content, $index_label_size, $index_label_col, $index_label_position, $index_label_angle, $angle_flag, $conf, $ratio, $id_line_height, $shift_angle_closed_feature, $orders)=@_;
	if($index_color=~ /rgb\(\d+,\d+,\d+\),[^,]/ or $index_color=~ /[^,],rgb\(\d+,\d+,\d+\)/){
		die "\nerror: should use ,, instead of , to separate the $index_color\n";
	}
	my @arr_cols = split(/,,/, $index_color);
	for my $c (@arr_cols){
		if($c!~ /^rgb/ && $c!~ /^#\d+$/ && $c!~ /^\w/){
			die "error: $c for @arr_cols of $feature_id is wrong color format\n";
		}
	}
	my $feature_opacity=&get_para("feature_opacity", $feature_id, $conf);
	#my $feature_opacity=1;
	my $shape=&get_para("feature_shape", $feature_id, $conf);
	my $feature_shift_y_unit=&get_para("feature_shift_y_unit", $feature_id, $conf);
	my $feature_shift_x=&get_para("feature_shift_x", $feature_id, $conf);

	if($feature_shift_x!~ /^[\+\-]?\d+\.?\d*$/){
		die "error: feature_shift_x format like 0 or +10 or -10, unit is bp\n"
	}
	$shift_x+=$feature_shift_x*$ratio;
	my $shift_unit=$id_line_height;
    	my @feature_shift_y_units = ("radius", "backbone", "percent");
	if($shape=~ /^circle_point/){
		if($feature_shift_y_unit=~ /radius/){
			$shift_unit=($end-$start)*$ratio;
		}elsif($feature_shift_y_unit=~ /backbone/){
			$shift_unit=$id_line_height;
		}elsif($feature_shift_y_unit=~ /percent/){
        		$shift_unit=($sample_single_height-$id_line_height-1)/100;
		}else{
			die "error: only support @feature_shift_y_units for feature_shift_y_unit, but not $feature_shift_y_unit\n";
		}
		#print "circle shift_unit is $shift_unit\n";
	}
	die "\nerror: not support $feature_shift_y_unit for $feature_id. only support @feature_shift_y_units\n" if(! grep(/^$feature_shift_y_unit$/, @feature_shift_y_units));
	if($feature_shift_y_unit=~ /percent/){
        	$shift_unit=($sample_single_height-$id_line_height-1)/100;
	}

	$feature_shift_y=~ s/^([1-9].*)/\+$1/;
	if($feature_shift_y=~ /^([+-])([\d\.]+)/){
		if($1 eq "+" || $1 eq ""){
			$shift_y +=  1 * $2 * $shift_unit + 0.5 * $id_line_height;
		}else{
			$shift_y += -1 * $2 * $shift_unit - 0.5 * $id_line_height;
		}
	}elsif($feature_shift_y=~ /^\s*0/){
		$shift_y +=0
	}else{
		die "error: for $feature_id, feature_shift_y is $feature_shift_y, but should be like +1 or -1, +2, so on\n"
	}
	my $order_f=&get_para("feature_order", $feature_id, $conf);
	my $order_f_label=&get_para("feature_label_order", $feature_id, $conf);
	my $padding_feature_label=&get_para("padding_feature_label", $feature_id, $conf);
	my $display_feature=&get_para("display_feature", $feature_id, $conf);
	my $display_feature_label=&get_para("display_feature_label", $feature_id, $conf);
	my $feature_stroke_color=&get_para("feature_border_color", $feature_id, $conf);
	my $feature_stroke_size=&get_para("feature_border_size", $feature_id, $conf);


	my ($back,$x1,$y1,$x2,$y2,$x3,$y3,$x4,$y4,$x5,$y5,$x6,$y6,$x7,$y7,$label_x,$label_y,$index_col_start,$index_col_end,$crossing_link_start_x,$crossing_link_start_y,$crossing_link_end_x,$crossing_link_end_y);
	my ($label_y_shift, $label_roat_angle);
	$back="";
	if($angle_flag){
		$shift_angle_closed_feature += $conf->{shift_angle_closed_feature};
	}else{
		$shift_angle_closed_feature = 0;
	}
	$gene_height_top=0 if($shape!~ /arrow/i);
	if($index_label_position=~ /_up$/){
		$label_y_shift= - $padding_feature_label;
		$index_label_angle = ($angle_flag)? $index_label_angle +$shift_angle_closed_feature:$index_label_angle; # 相邻feature的label的angle开
	}elsif($index_label_position=~ /_low$/){
		$label_y_shift= 2*$gene_height_top+$gene_height_medium + $padding_feature_label;
		$index_label_angle = ($angle_flag)? $index_label_angle -$shift_angle_closed_feature:$index_label_angle; # 相邻feature的label的angle开
	}elsif($index_label_position=~ /_medium$/){
		$label_y_shift= $gene_height_top+0.5*$gene_height_medium + $padding_feature_label;
		$index_label_angle = ($angle_flag)? $index_label_angle -$shift_angle_closed_feature:$index_label_angle; # 相邻feature的label的angle开
	}else{
		die "error:  not support $conf->{pos_feature_label} yet~\n"
	}
	my $start_title=$start;
	my $end_title=$end;
	if($conf->{absolute_postion_in_title}=~ /yes/i){
		$start_title=$start_raw;
		$end_title=$end_raw;
	}
	if($shape=~ /arrow/){

		if($strand){
			#以左上角为起始点，逆时针转一圈
			$x1=($start*$ratio+$shift_x);$y1=($sample_single_height - $gene_height_medium)/2+$shift_y;#gene_height_medium指arrow中间的高度
			$x2=$x1;$y2=$y1+$gene_height_medium;
			$x3=$x2+(1-$gene_width_arrow)*($end -$start)*$ratio;$y3=$y2;#gene_width_arrow指横向的arrow箭头的宽度
			$x4=$x3;$y4=$y3+$gene_height_top; ##gene_height_top是指arrow中间之外的一边尖尖的高度
			$x5=$x2+($end -$start)*$ratio;$y5=0.5*$sample_single_height+$shift_y;
			$x6=$x4;$y6=$y4 - 2*$gene_height_top - $gene_height_medium;
			$x7=$x3;$y7=$y1;
			$label_y=$y6+$label_y_shift;
			$crossing_link_start_x=$x1;
			$crossing_link_start_y=$y1+0.5*$gene_height_medium;
			$crossing_link_end_x=$x5;
			$crossing_link_end_y=$y5;
		}else{
			#负链以arrow左边尖尖为起始点，逆时针旋转一周
			$x1=($start*$ratio+$shift_x);$y1=0.5*$sample_single_height+$shift_y;
			$x2=$x1+$gene_width_arrow*($end -$start)*$ratio;$y2=$y1+0.5*$gene_height_medium+$gene_height_top;
			$x3=$x2;$y3=$y2 -$gene_height_top;
			$x4=$x3+(1-$gene_width_arrow)*($end -$start)*$ratio;$y4=$y3;
			$x5=$x4;$y5=$y4-$gene_height_medium;
			$x6=$x3;$y6=$y5;
			$x7=$x2;$y7=$y2 -2*$gene_height_top - $gene_height_medium;

			$label_y=$y7+$label_y_shift;
			$crossing_link_start_x=$x1;
			$crossing_link_start_y=$y1;
			$crossing_link_end_x=$x4;
			$crossing_link_end_y=$y4-0.5*$gene_height_medium;

		}

		if($index_label_position=~ /^medium_/){
			$label_x = $x1 + ($end - $start)/2 * $ratio;
		}elsif($index_label_position=~ /^left_/){
			$label_x = $x1;
		}elsif($index_label_position=~ /^right_/){
			$label_x = $x4;
		}else{
			die "error:  not support $conf->{pos_feature_label} yet~\n"
		}

		#print "index_color2 is $index_color\n";
		if(@arr_cols==2 && $display_feature=~ /yes/i){
			$index_col_start = $arr_cols[0];
			$index_col_end = $arr_cols[1];
			my $index_color_id = $index_color;
			$index_color_id=~ s/,/-/g;
			$index_color_id=~ s/\)/-/g;
			$index_color_id=~ s/\(/-/g;
			$orders->{$order_f}.="
			<defs>
			<linearGradient id=\"$index_color_id\" x1=\"0%\" y1=\"0%\" x2=\"0%\" y2=\"100%\">
			<stop offset=\"0%\" style=\"stop-color:$index_col_start;stop-opacity:1\"/>
			<stop offset=\"50%\" style=\"stop-color:$index_col_end;stop-opacity:1\"/>
			<stop offset=\"100%\" style=\"stop-color:$index_col_start;stop-opacity:1\"/>
			</linearGradient>
			</defs>
			<g style=\"fill:none\">
			<title>$feature_id,$sample,$id,$start_title,$end_title,$strand</title>
			<polygon points=\"$x1,$y1 $x2,$y2 $x3,$y3 $x4,$y4 $x5,$y5 $x6,$y6 $x7,$y7\" style=\"fill:url(#$index_color_id);stroke:$feature_stroke_color;stroke-width:$feature_stroke_size;opacity:$feature_opacity\"/> 
			</g>\n"; ## feture arrow
		}elsif($display_feature=~ /yes/i){
			$orders->{$order_f}.="
			<g style=\"fill:none\">
			<title>$feature_id,$sample,$id,$start_title,$end_title,$strand</title>
			<polygon points=\"$x1,$y1 $x2,$y2 $x3,$y3 $x4,$y4 $x5,$y5 $x6,$y6 $x7,$y7\" style=\"fill:$index_color;stroke:$feature_stroke_color;stroke-width:$feature_stroke_size;opacity:$feature_opacity\"/> 
			</g>\n"; ## feture arrow

		}



		## draw label of feature
		$orders->{$order_f_label}.= "<text x=\"$label_x\" y=\"$label_y\" font-size=\"${index_label_size}px\" fill=\"$index_label_col\"  text-anchor='start'   transform=\"rotate($index_label_angle $label_x $label_y)\" font-family=\"Times New Roman\">$index_label_content</text>\n" if($display_feature_label!~ /no/i && $display_feature_label!~ /no,no/i ); # label of feature
		# check this feature if is in crossing_link
		if(exists $conf->{crossing_link2}->{features}->{$feature_id}){
			#print "crossing_link $feature_id\n";
			$conf->{crossing_link2}->{position}->{$feature_id}->{start}->{x}=$crossing_link_start_x;
			$conf->{crossing_link2}->{position}->{$feature_id}->{start}->{y}=$crossing_link_start_y;

			$conf->{crossing_link2}->{position}->{$feature_id}->{end}->{x}=$crossing_link_end_x;
			$conf->{crossing_link2}->{position}->{$feature_id}->{end}->{y}=$crossing_link_end_y;
			#print "crossing_linkis $feature_id $crossing_link_start_x $crossing_link_start_y $crossing_link_end_x $crossing_link_end_y\n";
		}

	}elsif($shape=~ /^rect/){
		if($strand){
			#以左上角为起始点，逆时针转一圈
			$x1=($start*$ratio+$shift_x);$y1=($sample_single_height - $gene_height_medium)/2+$shift_y;#gene_height_medium指arrow中间的高度
			$x2=$x1;$y2=$y1+$gene_height_medium;
			$x3=$x2+($end -$start)*$ratio;$y3=$y2;
			$x4=$x3;$y4=$y1;

			$label_y=$y4+$label_y_shift;
			$crossing_link_start_x=$x1;
			$crossing_link_start_y=$y1+0.5*$gene_height_medium;
			$crossing_link_end_x=$x3;
			$crossing_link_end_y=$crossing_link_start_y;
		}else{
			#以左上角为起始点，逆时针转一圈
			$x1=($start*$ratio+$shift_x);$y1=($sample_single_height - $gene_height_medium)/2+$shift_y;#gene_height_medium指arrow中间的高度
			$x2=$x1;$y2=$y1+$gene_height_medium;
			$x3=$x2+($end -$start)*$ratio;$y3=$y2;
			$x4=$x3;$y4=$y1;

			$label_y=$y4+$label_y_shift;
			$crossing_link_start_x=$x1;
			$crossing_link_start_y=$y1+0.5*$gene_height_medium;
			$crossing_link_end_x=$x3;
			$crossing_link_end_y=$crossing_link_start_y;
		}

		if($index_label_position=~ /^medium_/){
			$label_x = $x1 + ($end - $start)/2 * $ratio;
		}elsif($index_label_position=~ /^left_/){
			$label_x = $x1;
		}elsif($index_label_position=~ /^right_/){
			$label_x = $x4;
		}else{
			die "error:  not support $conf->{pos_feature_label} yet~\n"
		}

		#print "y1 is $y1\n";
		#my ($feature_id,$start,$end,$strand,$gene_height_medium,$gene_height_top,$gene_width_arrow,$shift_x,$shift_y,$sample_single_height,$sample,$id, $index_color, $index_label, $index_label_content, $index_label_size, $index_label_col, $index_label_position, $index_label_angle)=@_;
		#print "index_color2 is $index_color\n";
		if(@arr_cols==2 && $display_feature=~ /yes/i){
			$index_col_start = $arr_cols[0];
			$index_col_end = $arr_cols[1];
			my $index_color_id = $index_color;
			$index_color_id=~ s/,/-/g;
			$index_color_id=~ s/\)/-/g;
			$index_color_id=~ s/\(/-/g;
			$orders->{$order_f}.="
			<defs>
			<linearGradient id=\"$index_color_id\" x1=\"0%\" y1=\"0%\" x2=\"0%\" y2=\"100%\">
			<stop offset=\"0%\" style=\"stop-color:$index_col_start;stop-opacity:1\"/>
			<stop offset=\"50%\" style=\"stop-color:$index_col_end;stop-opacity:1\"/>
			<stop offset=\"100%\" style=\"stop-color:$index_col_start;stop-opacity:1\"/>
			</linearGradient>
			</defs>
			<g style=\"fill:none\">
			<title>$feature_id,$sample,$id,$start_title,$end_title,$strand</title>
			<polygon points=\"$x1,$y1 $x2,$y2 $x3,$y3 $x4,$y4 \" style=\"fill:url(#$index_color_id);stroke:$feature_stroke_color;stroke-width:$feature_stroke_size;opacity:$feature_opacity\"/> 
			</g>\n"; ## feture rect
		}elsif($display_feature=~ /yes/i){
			$orders->{$order_f}.="
			<g style=\"fill:none\">
			<title>$feature_id,$sample,$id,$start_title,$end_title,$strand</title>
			<polygon points=\"$x1,$y1 $x2,$y2 $x3,$y3 $x4,$y4 \" style=\"fill:$index_color;stroke:$feature_stroke_color;stroke-width:$feature_stroke_size;opacity:$feature_opacity\"/> 
			</g>\n"; ## feture rect

		}



		## draw label of feature
		die "die:label_y is $label_y, id is $feature_id\n" if(!$label_y);
		$orders->{$order_f_label}.= "<text x=\"$label_x\" y=\"$label_y\" font-size=\"${index_label_size}px\" fill=\"$index_label_col\"  text-anchor='start'   transform=\"rotate($index_label_angle $label_x $label_y)\" font-family=\"Times New Roman\">$index_label_content</text>\n" if($display_feature_label!~ /no/i && $display_feature_label!~ /no,no/i); # label of feature
		# check this feature if is in crossing_link
		if(exists $conf->{crossing_link2}->{features}->{$feature_id}){
			#print "crossing_link $feature_id\n";
			$conf->{crossing_link2}->{position}->{$feature_id}->{start}->{x}=$crossing_link_start_x;
			$conf->{crossing_link2}->{position}->{$feature_id}->{start}->{y}=$crossing_link_start_y;

			$conf->{crossing_link2}->{position}->{$feature_id}->{end}->{x}=$crossing_link_end_x;
			$conf->{crossing_link2}->{position}->{$feature_id}->{end}->{y}=$crossing_link_end_y;
			#print "crossing_linkis $feature_id $crossing_link_start_x $crossing_link_start_y $crossing_link_end_x $crossing_link_end_y\n";
		}

	}elsif($shape=~ /^round_rect/){
		die "error: not support $shape yet~\n";
	}elsif($shape=~ /^circle_point/){
		my $center_point_x=$start*$ratio + $shift_x + ($end - $start)*$ratio*0.5;
		my $center_point_y=($sample_single_height - $gene_height_medium)/2 + $shift_y + 0.5*$gene_height_medium ;
		my $radius= ($end - $start)*$ratio*0.5 ; # 0.5*$gene_height_medium;
		my $x1=$start*$ratio+$shift_x;
		my $x4=$x1+($end-$start)*$ratio;
		my $crossing_link_start_x=$center_point_x;
		my $crossing_link_start_y=$center_point_y-$radius;
		my $crossing_link_end_x=$center_point_x;
		my $crossing_link_end_y=$center_point_y+$radius;
		if($index_label_position=~ /^medium_/){
			$label_x = $x1 + ($end - $start)/2 * $ratio;
		}elsif($index_label_position=~ /^left_/){
			$label_x = $x1;
		}elsif($index_label_position=~ /^right_/){
			$label_x = $x4;
		}else{
			die "error:  not support $conf->{pos_feature_label} yet~\n"
		}

		if(@arr_cols==2 && $display_feature=~ /yes/i){
			$index_col_start = $arr_cols[0];
			$index_col_end = $arr_cols[1];
			my $index_color_id = $index_color;
			$index_color_id=~ s/,/-/g;
			$index_color_id=~ s/\)/-/g;
			$index_color_id=~ s/\(/-/g;
			$orders->{$order_f}.="
			<defs>
			<linearGradient id=\"$index_color_id\" x1=\"0%\" y1=\"0%\" x2=\"0%\" y2=\"100%\">
			<stop offset=\"0%\" style=\"stop-color:$index_col_start;stop-opacity:1\"/>
			<stop offset=\"50%\" style=\"stop-color:$index_col_end;stop-opacity:1\"/>
			<stop offset=\"100%\" style=\"stop-color:$index_col_start;stop-opacity:1\"/>
			</linearGradient>
			</defs>
			<g style=\"fill:none\">
			<title>$feature_id,$sample,$id,$start_title,$end_title,$strand</title>
			<circle cx=\"$center_point_x\" cy=\"$center_point_y\" r=\"$radius\" stroke=\"$feature_stroke_color\" stroke-width=\"$feature_stroke_size\" fill=\"$index_color\" style=\"opacity:$feature_opacity\" />
			</g>\n"; ## feture rect
		}elsif($display_feature=~ /yes/i){
			$orders->{$order_f}.="
			<g style=\"fill:none\">
			<title>$feature_id,$sample,$id,$start_title,$end_title,$strand</title>
			<circle cx=\"$center_point_x\" cy=\"$center_point_y\" r=\"$radius\" stroke=\"$feature_stroke_color\" stroke-width=\"$feature_stroke_size\" fill=\"$index_color\" style=\"opacity:$feature_opacity\"/>

			</g>\n"; ## feture rect

		}



		## draw label of feature
		$orders->{$order_f_label}.= "<text x=\"$label_x\" y=\"$label_y\" font-size=\"${index_label_size}px\" fill=\"$index_label_col\"  text-anchor='start'   transform=\"rotate($index_label_angle $label_x $label_y)\" font-family=\"Times New Roman\">$index_label_content</text>\n" if($display_feature_label!~ /no/i && $display_feature_label!~ /no,no/i); # label of feature
		# check this feature if is in crossing_link
		if(exists $conf->{crossing_link2}->{features}->{$feature_id}){
			#print "crossing_link $feature_id\n";
			$conf->{crossing_link2}->{position}->{$feature_id}->{start}->{x}=$crossing_link_start_x;
			$conf->{crossing_link2}->{position}->{$feature_id}->{start}->{y}=$crossing_link_start_y;

			$conf->{crossing_link2}->{position}->{$feature_id}->{end}->{x}=$crossing_link_end_x;
			$conf->{crossing_link2}->{position}->{$feature_id}->{end}->{y}=$crossing_link_end_y;
		}

	}else{
		die "error: not support $shape yet~\n";
	}


	return ($back, $shift_angle_closed_feature, $orders);	

}
sub display_conf(){
	my (%conf) = @_;
	foreach my $k (keys %conf){
		if($k eq "sample_name_old2new"){
			foreach my $old(keys %{$conf{$k}}){
				print "$k\t$old\t$conf{$k}{$old}\n";
			}
		}elsif($k eq "feature_setting"){
			foreach my $f(keys %{$conf{$k}}){
				foreach my $e(keys %{$conf{$k}{$f}}){
					print "$k\t$f\t$e\t$conf{$k}{$f}{$e}\n";
				}
			}
		}elsif($k eq "crossing_link"){
			foreach my $n(keys %{$conf{$k}}){
				#print "$k\t$n\t@{$conf{$k}{$n}}\n";
				print "$k\t$n\t\n";
			}
		}elsif($k eq "scaffold_order"){
			for my $s(keys %{$conf{$k}}){
				for my $index(keys %{$conf{$k}{$s}}){
					print "$k\t$s\t$index\t$conf{$k}{$s}{$index}\n";
				}
			}
		}else{
			print "$k : $conf{$k}\n";
		}

	}
}

sub read_conf(){
	my ($conf,@funcs) = @_;
	my %confs;
	open IN, "$conf" or die "$!";
	while(<IN>){
		chomp;
		next if($_=~ /^#/ || $_=~ /^\s*$/);
		die "error: need = in $_ of $conf~\n" if($_!~ /=/);
		$_=~ s/([^=^\s])\s+#.*$/$1/g;
		my ($key, $value) = split(/\s*=\s*/, $_);
		$value=~ s/\s+$//;
		$value=~ s/^\s+//;

		if($key eq ""){
			die "error format: $_\n";
		}
		if($value eq ""){
			die "error format: $_\n";
		}
        if(grep(/^$key$/, @funcs)){
		    push @{$confs{$key}},$value;
        }else{
		    $confs{$key} = $value;
        }
		print "$key -> $value\n";
	}
	close IN;
	return %confs;

}

sub default_setting(){
	my (%conf) = @_;
	$conf{svg_width_height} ||= '600,1500';
	#$conf{anchor_positon_ratio} ||= 1;
	$conf{pdf_dpi} ||=100;
	$conf{top_bottom_margin} ||=0.1;
	$conf{genome_height_ratio} ||= 1;
	$conf{feature_height_ratio} ||= 1.5;
	$conf{feature_height_unit} ||= "backbone"; # or percent
	$conf{space_between_blocks} ||= 500; # bp
	$conf{feature_label_size} ||=10;
	$conf{feature_label_color} ||="black";
	$conf{label_rotate_angle} =(exists $conf{label_rotate_angle})? $conf{label_rotate_angle}:-60;
	$conf{feature_color} ||= 'ForestGreen'; #ForestGreen,LimeGreen
	$conf{color_sample_name_default} ||= 'green';
	$conf{sample_name_color_default} ||='black';
	$conf{sample_name_font_size_default} ||=15;
	$conf{legend_font_size} ||= 15; #legend中文字字体大小
	$conf{legend_height_percent} ||= 0.2; # legends的高度占整个图高度的比例
	$conf{legend_width_margin} ||= 0.1; # legends左右两侧的margin
	$conf{legend_width_textpercent} ||= 0.6; # l
	$conf{feature_shape} ||= 'arrow'; # arrow or rect or circle_point, not support round_rect yet
	$conf{track_style} ||="fill:green";
	$conf{padding_feature_label} ||= 3;
	$conf{pos_feature_label} ||="medium_up";
	$conf{distance_closed_feature} ||=50;
	$conf{shift_angle_closed_feature} ||=10;
	$conf{feature_arrow_sharp_extent} =(exists $conf{feature_arrow_sharp_extent})? $conf{feature_arrow_sharp_extent}:0.3;
	$conf{scale_display} ||="no";
	$conf{scale_position} ||="low";
	$conf{display_feature} ||="yes";
	$conf{legend_stroke_color} ||="black";
	$conf{legend_stroke_width} ||=0;
	$conf{track_order}=(defined $conf{track_order})? $conf{track_order}:0;
	$conf{feature_order} =(defined $conf{feature_order})? $conf{feature_order}:1;
	$conf{feature_label_order} =(defined $conf{feature_label_order})? $conf{feature_label_order}:1;
	$conf{cross_link_order} =(defined $conf{cross_link_order})? $conf{cross_link_order}:2; # bigger mean upper 
	$conf{cross_link_opacity} ||=1;
	$conf{display_feature_label} ||="yes";
	$conf{display_legend} ||="yes";
	$conf{cross_link_anchor_pos} ||="medium_medium";
	$conf{ignore_sharp_arrow} ||="no";
	$conf{scale_color} ||="black";
	$conf{scale_width} ||=1;
	$conf{scale_ratio} ||=100;
	$conf{scale_padding_y} ||=-0.1;
	$conf{scale_tick_height} ||=0.01;
	$conf{scale_tick_opacity} ||=0.5;
	$conf{scale_order} ||=0;
	$conf{scale_tick_padding_y} ||=10;
	$conf{scale_tick_fontsize} ||=10;
	$conf{feature_arrow_width_extent} ||=0.7;
	$conf{connect_with_same_scaffold} ||="yes";
	$conf{connect_stroke_dasharray} ||="2,2";
	$conf{connect_stroke_width} ||=2;
	$conf{connect_stroke_color} ||="black";
	$conf{absolute_postion_in_title} ||="yes";
	$conf{feature_shift_y} ||=0;
	$conf{feature_shift_x} ||=0;
	$conf{feature_border_size} ||=0;
	$conf{feature_border_color} ||="black";
	$conf{feature_opacity} =(exists $conf{feature_opacity})? $conf{feature_opacity}:1;
	$conf{cross_link_orientation} ||="forward";
	$conf{cross_link_color} ||="#FF8C00";
	$conf{cross_link_color_reverse} ||="#3CB371";
	$conf{feature_shift_y_unit} ||="backbone"; # radius or backbone or percent
	$conf{cross_link_orientation_ellipse} ||="up";
	$conf{cross_link_shape} ||="quadrilateral";
	$conf{cross_link_height_ellipse} ||="10,8";
	$conf{svg_background_color} ||="white";
	$conf{feature_label_auto_angle_flag} =(exists $conf{feature_label_auto_angle_flag})? $conf{feature_label_auto_angle_flag}:1;
	##$conf{feature_ytick_region} ||="0-3:0-10;";
	##$conf{feature_ytick_hgrid_line} =(exists $conf{feature_ytick_hgrid_line})? $conf{feature_ytick_hgrid_line}:0;

	if($conf{track_style}!~ /:/){
		die "error: track_style format like  fill:blue;stroke:pink;stroke-width:5;fill-opacity:0.1;stroke-opacity:0.9\n";
	}
	if($conf{feature_shift_x}!~ /^\d+$/){
		die "error:feature_shift_x format like 0 or +10 or -10, unit is bp\n"
	}

    
	my @track_reorder;
	if(exists $conf{tracks_reorder}){
        open OR,"$conf{tracks_reorder}" or die "$!";
		while(<OR>){
			chomp;
			next if($_=~ /^\s*#/ || $_=~ /^\s*$/);
			push @track_reorder, $_;
		}
		close OR;
	}

	#sample_name_old2new
	if(exists $conf{sample_name_old2new}){
		if(-e $conf{sample_name_old2new}){
			open IN,"$conf{sample_name_old2new}" or die "$!";
			while(<IN>){
				chomp;
				next if($_=~ /^#/ || $_=~ /^\s*$/);
				my @arr = split(/\t+/, $_);
				if(@arr == 2){
					$conf{sample_name_old2new2}{$arr[0]}{new_name} = $arr[1]; ## old sample name to new sample name
					$conf{sample_name_old2new2}{$arr[0]}{new_color} = $conf{sample_name_color_default};
					$conf{sample_name_old2new2}{$arr[0]}{new_font_size} = $conf{sample_name_font_size_default};
					#die "error line$.:$_, use tab to seprate new and old name, $arr[0] has not new name in $conf{'sample_name_old2new'} for sample_name_old2new\n";
					#
				}elsif(@arr == 4){
					$conf{sample_name_old2new2}{$arr[0]}{new_name} = $arr[1]; ## old sample name to new sample name
					$conf{sample_name_old2new2}{$arr[0]}{new_color} = $arr[2];
					$conf{sample_name_old2new2}{$arr[0]}{new_font_size} = $arr[3];
				}else{
					die "error line$.:$_, use tab to seprate new and old name, $arr[0] has not new name in $conf{'sample_name_old2new'} for sample_name_old2new\n";

				}
				#print "2 sample_name_old2new $arr[0] $arr[1]\n";
			}
			close IN;
		}else{
			die "for sample_name_old2new: $conf{sample_name_old2new} file not exists!\n";
		}
	}

	##feature_setting
	if(exists $conf{feature_setting}){
		if(-e $conf{feature_setting}){
			open IN,"$conf{feature_setting}" or die "$!";
			while(<IN>){
				chomp;
				next if($_=~ /^#/ || $_=~ /^\s*$/);
				last if($_ eq "exit");
				$_=~ s/#\s+.*$//;
				$_=~ s/\s+$//;

				my @arr;
                if($_=~ /\s+\S+_label\s+/){
                   @arr=split(/\t+/, $_);
                }else{
                   @arr=split(/\s+/, $_);
                }
				if(@arr!=3){
                    my $tmp=scalar(@arr);
                    for my $k(@arr){print "$k\n"}
                    die "error: $conf{feature_setting} should only have 3 columns seperate by \\t, but $_ has $tmp\n "
                }
				$conf{feature_setting2}{$arr[0]}{$arr[1]}=$arr[2];
				#if($arr[0]=~ /s2000.3.2000.6000/){
					#print "s2000.3.2000.6000 is ,$arr[0],$arr[1],$arr[2], line is $_\n";
				#}
			}
			close IN;

		}else{
			die "for feature_setting: $conf{feature_setting} file not exists!\n";
		}
	}

	##crossing_link
	if(exists $conf{crossing_link}){
		if(-e $conf{crossing_link}){
			open IN,"$conf{crossing_link}" or die "$!";
			while(<IN>){
				chomp;
				next if($_=~ /^#/ || $_=~ /^\s*$/);
				$_=~ s/#\s+\S+.*$//;
				$_=~ s/\s+$//;
				my @arr;
				if($_=~ /^\S+,\S/){
					$_=~ s/,\s*$//;
					@arr = split(",", $_);
					foreach my $k(0..(scalar @arr -1)){
						$conf{crossing_link2}{index}{"$arr[$k],$arr[$k+1]"}{'id'} = "" if ($k != (scalar @arr -1));
					}

				}elsif($_=~ /\t/){
					@arr = split("\t", $_);
					my $len=scalar@arr;
					die "error: line is $_\nwrong format of $_ of $conf{crossing_link}, should have four columns not $len~\n" if (@arr!=4);
					$conf{crossing_link2}{index}{"$arr[0],$arr[1]"}{$arr[2]} = $arr[3];
					@arr = ($arr[0],$arr[1]);
				}else{
					die "error: wrong format $_ of $conf{crossing_link2}\n";
				}
				foreach my $k(@arr){
					$conf{crossing_link2}{features}{$k} = '';
				}
			}
			close IN;

		}else{
			die "for crossing_link: $conf{crossing_link} file not exists!\n";
		}
	}

	##arange scaffold order to display
	if(exists $conf{scaffold_order}){
		if(-e $conf{scaffold_order}){
			open IN,"$conf{scaffold_order}" or die "$!";
			while(<IN>){
				chomp;
				next if($_=~ /^#/);
				$_=~ s/\s*$//;
				$_=~ s/^\s*//;
				my @arr = split(/\t+/, $_);
				for my $i(1..(scalar(@arr)-1)){
					$conf{scaffold_order}{$arr[0]}{$arr[$i]} = $i; ##sample11	NC_00581666	NC_005816
				}
				#print "4 crossing_link $. @arr\n";
			}
			close IN;
		}else{
			die "for scaffold_order: $conf{scaffold_order} file not exists!\n";
		}
	}

	return (\%conf, \@track_reorder);

}


sub check_track_order(){
    my @track_order=@{$_[0]};
    my @track_reorder=@{$_[1]};
	return 1 if(@track_reorder ==0);
	my $len = scalar(@track_order);
	my $len_re = scalar(@track_reorder);
	if($len != $len_re){
		die "error: track_reorder has $len_re tracks which is not equal to --list\n";
	}else{
		@track_order = @track_reorder;
	}

    return @track_order;
}


sub check_para(){
    my (%conf)=@_;
    my @paras=("absolute_postion_in_title","connect_stroke_color","connect_stroke_dasharray","connect_stroke_width","connect_with_same_scaffold","cross_link_anchor_pos","cross_link_color","cross_link_height_ellipse","cross_link_opacity","cross_link_order","cross_link_orientation_ellipse","cross_link_shape","crossing_link","default_legend", "plot_depth", "display_feature","display_feature_label","display_legend","distance_closed_feature","feature_arrow_sharp_extent","feature_arrow_width_extent","feature_border_color","feature_border_size","feature_color","feature_height_ratio","feature_keywords","feature_label_auto_angle_flag","feature_label_color","feature_label_order","feature_label_size","feature_order","feature_setting","feature_shape","feature_shift_x","feature_shift_y","feature_shift_y_unit", "genome_height_ratio","ignore_sharp_arrow","label_rotate_angle","legend_font_size","legend_height_ratio","legend_height_space","legend_stroke_color","legend_stroke_width","legend_width_margin","legend_width_textpercent","lr_mapping","padding_feature_label","pdf_dpi","pos_feature_label","sample_name_color_default","sample_name_font_size_default","sample_name_old2new","scale_color","scale_display","scale_order","scale_padding_y","scale_position","scale_ratio","scale_tick_fontsize","scale_tick_height","scale_tick_opacity","scale_tick_padding_y","scale_width","shift_angle_closed_feature","space_between_blocks","sr_mapping","svg_background_color","svg_width_height","top_bottom_margin","track_order","track_style","width_ratio_ref_cluster_legend", "cross_link_color_reverse", "feature_opacity", "color_sample_name_default", "cross_link_orientation", "legend_height_percent","feature_height_unit", "sample_name_old2new2", "crossing_link2", "feature_setting2");
    for my $k (keys %conf){
        die "\nerror: not support $k in --conf . only support @paras\n" if(!grep(/^$k$/, @paras));
    }
    print "check done\n";
}
