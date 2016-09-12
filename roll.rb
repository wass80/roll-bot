class Roll
  def initialize res
    raise "unmatch" unless Array === res
    raise "non int" unless Integer === res[0]
    @res = res
  end
  def self.[] *args
    self.new(args)
  end
  def res
    @res
  end
  def roll
    @res.sample
  end
  def exp
    Rational(@res.reduce(&:+), @res.size)
  end
  def var
    e = self.exp
    @res.reduce(0){|a,n|a + (n - e) ** 2}/self.res.size
  end
  def map
    Roll.new(@res.flat_map{|r| (yield r).res})
  end
  def bimap other
    Roll.new(@res.flat_map{|r| other.res.flat_map{|o| yield r, o}})
  end
  def + other
    self.bimap other, &:+
  end
  def - other
    self.bimap other, &:-
  end
  def * other
    self.bimap other, &:*
  end
  def / other
    self.bimap(other){|r, l| (r + l - 1) / l }
  end
  def D other
    self.bimap(other){|r,l|
      [[*1..l]].cycle(r).reduce{|a, b| a.flat_map{|x| b.map{|y|x+y}}
    }}
  end
  def min other
    self.bimap(other){|r,l| [r,l].min}
  end
  def max other
    self.bimap(other){|r,l| [r,l].max}
  end
  def trim other1, other2
    self.bimap(other1){|r,l| [r,l].max}.
         bimap(other2){|r,l| [r,l].min}
  end
  def step other1
    self.bimap(other1){|r,l| if r >= l then 1 else 0 end}
  end
  def cat *others
    Roll.new(others.reduce(self.res){|a,n| a + n.res})
  end
  def rep times
    [self].cycle(times)
  end
  def stepc times, hit
    times.map{|t|
       rep(t).map{|s|s.step(hit)}.reduce{|r,l| r + l}
    }
  end
  def == other
    @res.sort == other.res.sort
  end
  def to_s
    "#{@res.sort} E:#{self.exp.to_f.round(2)} V:#{self.var.to_f.round(2)}"
  end
end

def tokenizer str
  str.scan(/\d+|\(|\)|[a-z]+|D|[+\-*\/]|,/)
end

def paser tok
# <expr>  ::= <term1> (('+' | '-') <term1>)*
# <term1> ::= <term2> (('*' | '/') <term1>)*
# <term2> ::= <term3> ('D'+ <term3>)*
# <term3> ::= '-' <digit>+ | <digit>+ | <symbol>* '(' <expr> ( ',' <expr> )* ')' | '(' <expr> ')'

  ast, rest, err = p_expr(tok)

  if err || !rest.empty?
    raise "#{err} :: #{rest}"
  else
    ast
  end
end

def combop ops, tok, &p_next
  ast, rest, err = p_next[tok]
  return [nil, tok, "combp #{ops} : #{err}"] if err

  ast_array = []

  until ops[rest[0]].nil?
    op = ops[rest[0]]
    new_ast, new_rest, err = p_next[rest[1..-1]]
    return [nil, tok, "combp #{ops}, #{rest} : #{err}"] if err

    ast_array << [op, new_ast]
    rest = new_rest
  end

  res = ast_array.reduce(ast){|astL, (op, astR)| [op, astL, astR]}
  [res, rest, nil]
end

def p_expr tok
  combop Hash[[["+", :+], ["-", :-]]], tok, &method(:p_term1)
end

def p_term1 tok
  combop Hash[[["*", :*], ["/", :/]]], tok, &method(:p_term2)
end

def p_term2 tok
  rest = tok
  res = []
  ast, new_rest, err = p_term3(rest)
  if err
    res << [:num, 1]
  else
    res << ast
    rest = new_rest
  end
  while rest[0] == "D"
    rest = rest[1..-1]
    ast, new_rest, err = p_term3(rest)
    if err
      res << [:num, 6]
    else
      res << ast
      rest = new_rest
    end
  end
  if res == [:num, 1]
    return [[], tok, "p_term2"]
  else
    return [res.reduce{|astR, astL| [:D, astR, astL]}, rest, nil]
  end
end

def p_term3 tok
  return [[], tok, "p_term3"] if tok.empty?
  case tok[0]
  when  "-"
    if tok[1].match(/^\d+$/)
      return [[:num, -1*tok[1].to_i], tok[2..-1], nil]
    else
      return [[], tok, "p_term3"]
    end
  when /^\d+$/
    return [[:num, tok[0].to_i], tok[1..-1], nil]
  when /^[a-z]+$/
    if tok[1] == "("
      args = []
      rest = tok[2..-1]
      loop do
        ast, rest, err = p_expr(rest)
        unless err
          args << ast
          case rest[0]
          when ")"
            return [[:call, tok[0], *args], rest[1..-1], nil]
          when ","
            rest = rest[1..-1]
            next
          end
          break
        end
      end
      return [[], tok, "p_term3"]
    else
      [[:var, tok[0]], tok[1..-1], nil] 
    end
  when "("
    ast, rest, err = p_expr(tok[1..-1])
    if !err && rest[0] == ")"
        return [ast, rest[1..-1], nil]
    end
  else
      return [[], tok, "p_term3"]
  end
end

def evaluate ast
  case ast[0]
  when :+
    evaluate(ast[1]) + evaluate(ast[2])
  when :-
    evaluate(ast[1]) - evaluate(ast[2])
  when :*
    evaluate(ast[1]) * evaluate(ast[2])
  when :/
    evaluate(ast[1]) / evaluate(ast[2])
  when :D
    evaluate(ast[1]).D(evaluate(ast[2]))
  when :num
    Roll[ast[1]]
  when :call
    f = ast[1]
    arg1 = evaluate(ast[2])
    args = ast[3..-1].map{|a|evaluate a}
    arg1.send(f, *args)
  else
    raise "no match"
  end
end

def getRoll str
  evaluate(paser(tokenizer(str)))
end

if __FILE__ == $0

require "minitest/autorun"

class TestRoll < MiniTest::Unit::TestCase
  def test_tokenizer
    tokens  = %w(hoge 2 piyo 3 D ( ) huga + - * / ,)
    assert_equal tokenizer(tokens.join(" ")), tokens
    assert_equal tokenizer(tokens.join("")), tokens
  end
  def test_paser_1
    assert_equal paser(tokenizer("1 + 1 * 1")),
      [:+, [:num, 1], [:*, [:num, 1], [:num, 1]]]
  end
  def test_paser_2
    assert_equal paser(tokenizer("1 + D1")),
      [:+, [:num, 1], [:D, [:num, 1], [:num, 1]]]
  end
  def test_paser_3
    assert_equal paser(tokenizer("D")),
      [:D, [:num, 1], [:num, 6]]
  end
  def test_paser_4
    assert_equal paser(tokenizer("1D")),
      [:D, [:num, 1], [:num, 6]]
  end
  def test_paser_5
    assert_equal paser(tokenizer("D1")),
      [:D, [:num, 1], [:num, 1]]
  end
  def test_paser_6
    assert_equal paser(tokenizer("DD")),
      [:D, [:D, [:num, 1], [:num, 6]], [:num, 6]]
  end
  def test_paser_7
    assert_equal paser(tokenizer("aaa + bbb")),
      [:+, [:var, "aaa"], [:var, "bbb"]]
  end
  def test_paser_8
    assert_equal paser(tokenizer("aaa ( 1 D 2 )")),
      [:call, "aaa",  [:D, [:num, 1], [:num, 2]]]
  end
  def test_roll_plus
    assert_equal Roll[1,2] + Roll[2,3], Roll[3,4,4,5]
  end
  def test_roll_div
    assert_equal Roll[1,2,3,4,5,6] / Roll[3], Roll[1,1,1,2,2,2]
  end
  def test_roller
    assert_equal Roll[1,2].D(Roll[2]), Roll[1,2,2,3,3,4]
  end
  def test_roll
    10.times{
      assert (1..6) ===  Roll[1].D(Roll[6]).roll
    }
  end
  def test_exp
    assert_equal Roll[1].D(Roll[6]).exp, 3.5r
  end
  def test_var
    assert_equal Roll[1].D(Roll[6]).var, 35/12r
  end
  def test_getRoll
    assert_equal getRoll("D"), Roll[1,2,3,4,5,6]
  end
  def test_min
    assert_equal getRoll("min(D,3)"), Roll[1,2,3,3,3,3]
  end
  def test_max
    assert_equal getRoll("max(D,3)"), Roll[3,3,3,4,5,6]
  end
  def test_trim
    assert_equal getRoll("trim(D,2,5)"), Roll[2,2,3,4,5,5]
  end
  def test_step
    assert_equal getRoll("6*step(D,6)"), Roll[0,0,0,0,0,6]
  end
  def test_cat
    assert_equal getRoll("cat(1,2,3)"), Roll[1,2,3]
  end
  def test_stepc
    assert_equal getRoll("stepc(D3,2,3)"), Roll[0,0,0,0,1,1,1,1,2]
  end
end
end
