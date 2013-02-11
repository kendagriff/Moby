require 'live_ast'
require 'live_ast/to_ruby'

class Context
  #meta programming
  @roles
  @interactions
  @defining_role
  @parent_role
  @role_alias
  @temp
  @alias_list
  #meta end

  def initialize
    @roles = Hash.new
    @interactions = Hash.new
    @parent_role = Array.new
    @role_alias = Array.new
  end

  def self.define(name, &block)
    ctx = Context.new
    ctx.instance_eval &block
    ctx.finalize name
  end
  def add_alias (a,role_name)
    @temp,@alias_list = nil
    @role_alias.last()[a] = role_name
  end
  def role_aliases
    @alias_list if @alias_list
    @alias_list = Hash.new
    @role_alias.each {|aliases|
      aliases.each {|k,v|
        @alias_list[k] = v
      }
    }
    @alias_list
  end
  def roles
    @temp if @temp
    @roles unless @role_alias and @role_alias.length
    @temp = Hash.new
    @roles.each {|k,v|
       @temp[k] = v
    }
    role_aliases.each {|k,v|
      @temp[k] = @roles[v]
    }
    @temp
  end
  def finalize(name)
    c = Class.new
    Kernel.const_set name, c
    code = ''
    fields = ''
    getters = ''
    impl = ''
    interactions = ''
    @interactions.each do |method_name, method_source|
      interactions << "  #{lambda2method(method_name, method_source)}"
    end
    @roles.each do |role, methods|
        fields << "@#{role}\n"
        getters << "def #{role};@#{role} end\n"

        methods.each do |method_name, method_source|
          rewritten_method_name = "self_#{role}_#{method_name}"
          definition = lambda2method rewritten_method_name, method_source
          impl << "  #{definition}" if definition
        end
    end

    code << "#{interactions}\n#{fields}\n  private\n#{getters}\n#{impl}\n"

    File.open("#{name}_generate.rb", 'w') { |f| f.write("class #{name}\r\n#{code}\r\nend") }
    c.class_eval(code)
  end

  def role(role_name)
    @defining_role = role_name
    @roles[role_name] = Hash.new
    yield if block_given?
    @defining_role = nil
  end

  def methods
    (@defining_role ? @roles[@defining_role] : @interactions)
  end

  def role_or_interaction_method(method_name, &b)
    p "method with out block #{method_name}" unless b

    args, block = block2source b.to_ruby, method_name
    args = "|#{args}|" if args
    source = "(proc do #{args}\n #{block}\nend)"
    methods[method_name] = source
  #rescue  StandardError => e
  #  p "Blew up #{method_name} with the exception #{e}"
  end

  alias method_missing role_or_interaction_method

  def role_method_call(ast, method)
    is_call_expression = ast && ast[0] == :call
    self_is_instance_expression = is_call_expression && (!ast[1] || ast[1] == :self) #implicit or explicit self
    is_in_block = ast && ast[0] == :lvar
    role_name_index = self_is_instance_expression ? 2 : 1
    role = (self_is_instance_expression || is_in_block) ? roles[ast[role_name_index]] : nil #is it a call to a role getter
    is_role_method = role && role.has_key?(method)
    role_name = is_in_block ? role_aliases[ast[1]] : (ast[2] if self_is_instance_expression)
    role_name if is_role_method #return role name
  end

  def lambda2method (method_name, method_source)
    evaluated = ast_eval method_source, binding
    ast = evaluated.to_ast
    transform_ast ast
    args, block = block2source LiveAST.parser::Unparser.unparse(ast), method_name
    args = "(#{args})" if args
    "\ndef #{method_name} #{args}\n#{block} end\n"
  end

  def transform_block(exp)
       if exp && exp[0] == :iter
           (1..(exp.length)).each do |i|
             changed = false
             expr = exp[i]
             #find the block
             if expr  && expr.length && expr[0] == :block
               block = expr
               expr = expr[1]
               #check if the first call is a bind call
               if expr && expr.length && (expr[0] == :call && expr[1] == nil && expr[2] == :bind)

                   arglist = expr[3]
                   if arglist && arglist[0] == :arglist
                     arguments = arglist[1]
                     if arguments && arguments[0] == :hash
                       block.delete_at 1
                       count = (arguments.length-1) / 2
                       (1..count).each do |j|
                         temp = j * 2
                         local = arguments[temp-1][1]
                         if local.instance_of? Sexp
                           local = local[1]
                         end
                         raise 'invalid value for role alias' unless local.instance_of? Symbol
                         #find the name of the role being bound to
                         aliased_role = arguments[temp][1]
                         if aliased_role.instance_of? Sexp
                           aliased_role = aliased_role[1]
                         end
                         raise "#{aliased_role} used in binding is an unknown role #{roles}" unless aliased_role.instance_of? Symbol and @roles.has_key? aliased_role
                         add_alias local,aliased_role

                         #replace bind call with assignment of iteration variable to role field
                         changed = true
                         assignment = Sexp.new
                         assignment[0] = :iasgn
                         assignment[1] = "@#{aliased_role}".to_sym
                         load_arg = Sexp.new
                         load_arg[0] = :lvar
                         load_arg[1] = local
                         assignment[2] = load_arg
                         block.insert 1,assignment

                         # assign role player to temp
                         temp_symbol = "temp____#{aliased_role}".to_sym
                         assignment = Sexp.new
                         assignment[0] = :lasgn
                         assignment[1] = temp_symbol
                         load_field = Sexp.new
                         load_field[0] = :ivar
                         load_field[1] = "@#{aliased_role}".to_sym
                         assignment[2] = load_field
                         block.insert 1,assignment

                         # reassign original player
                         assignment = Sexp.new
                         assignment[0] = :iasgn
                         assignment[1] = "@#{aliased_role}".to_sym
                         load_temp = Sexp.new
                         load_temp[0] = :lvar
                         load_temp[1] = temp_symbol
                         assignment[2] = load_temp
                         block[block.length] = assignment
                       end
                     end
                   end
               end
             end
             transform_ast exp if changed
           end
       end
  end

  def transform_ast(ast)
    if ast
      (0..(ast.length)).each do |k|
        exp = ast[k]
        if exp
          method_name = exp[2]
          role = role_method_call exp[1], exp[2]
          if exp[0] == :iter
            @role_alias.push Hash.new
            transform_block exp
            @role_alias.pop()
          end
          if exp[0] == :call && role
            exp[1] = nil #remove call to attribute
            exp[2] = "self_#{role}_#{method_name}".to_sym
          end
          if exp.instance_of? Sexp
            transform_ast exp
          end
        end
      end
    end
  end

  #cleans up the string for further processing and separates arguments from body
  def block2source(b, method_name)

    args = nil
    block = b.strip
    block = block[method_name.length..-1].strip if block.start_with? method_name.to_s
    block = cleanup_head_and_tail(block)
    if block.start_with? '|'
      args = block.scan(/\|([\w\d,\s]*)\|/)
      if args.length && args[0]
        args = args[0][0]
      else
        args = nil
      end
      block = block[(2 + (block[1..-1].index '|'))..-1].strip
    end
    return args, block
  end

  # removes proc do/{ at start and } or end at the end of the string
  def cleanup_head_and_tail(block)
    index = 0
    if /^proc\s/.match(block)
      block = block['proc'.length..-1].strip
    end
    if /^do\s/.match(block)
      block = block[2..-1].strip
    elsif block.start_with? '{'
      block = block[1..-1].strip
    end


    if /end$/.match(block)
      block = block[0..-4]
    elsif /\}$/.match(block)
      block = block[0..-2]
    end
    block
  end

  #separates the arguments from the body
  def get_arguments_and_body(block)
    index = block =~ /[^{do \t]/
    raise "invalid block source \n#{block}" unless index

    block = block[index..-1]
    index = block.index '|'
    line_end = block =~ /[^| ]/
    if index and (!line_end || index < line_end) #arguments supplied
      block = block[1..-1]
      index = (block.index '|')
      line_end = block[0..-1] =~ /[^a-z,A-Z0-9 |_]/
      index = 1 if !index or index > line_end
      args = block[0..index-1]
      block = block[index+1..-1]
      index = 0
    else
      args = nil
      index = 0
    end
    return args, block, index
  end
end