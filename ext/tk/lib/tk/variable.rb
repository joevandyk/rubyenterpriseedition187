#
# tk/variable.rb : treat Tk variable object
#
require 'tk'

class TkVariable
  include Tk
  extend TkCore

  include Comparable

  #TkCommandNames = ['tkwait'.freeze].freeze
  TkCommandNames = ['vwait'.freeze].freeze

  #TkVar_CB_TBL = {}
  #TkVar_ID_TBL = {}
  TkVar_CB_TBL = TkCore::INTERP.create_table
  TkVar_ID_TBL = TkCore::INTERP.create_table
  Tk_VARIABLE_ID = ["v".freeze, "00000".taint].freeze

  #TkCore::INTERP.add_tk_procs('rb_var', 'args', 
  #     "ruby [format \"TkVariable.callback %%Q!%s!\" $args]")
TkCore::INTERP.add_tk_procs('rb_var', 'args', <<-'EOL')
    if {[set st [catch {eval {ruby_cmd TkVariable callback} $args} ret]] != 0} {
       set idx [string first "\n\n" $ret]
       if {$idx > 0} {
          global errorInfo
          set tcl_backtrace $errorInfo
          set errorInfo [string range $ret [expr $idx + 2] \
                                           [string length $ret]]
          append errorInfo "\n" $tcl_backtrace
          bgerror [string range $ret 0 [expr $idx - 1]]
       } else {
          bgerror $ret
       }
       return ""
       #return -code $st $ret
    } else {
        return $ret
    }
  EOL

  #def TkVariable.callback(args)
  def TkVariable.callback(id, name1, name2, op)
    #name1,name2,op = tk_split_list(args)
    #name1,name2,op = tk_split_simplelist(args)
    if TkVar_CB_TBL[id]
      #_get_eval_string(TkVar_CB_TBL[name1].trace_callback(name2,op))
      begin
        _get_eval_string(TkVar_CB_TBL[id].trace_callback(name2, op))
      rescue SystemExit
        exit(0)
      rescue Interrupt
        exit!(1)
      rescue Exception => e
        begin
          msg = _toUTF8(e.class.inspect) + ': ' + 
                _toUTF8(e.message) + "\n" + 
                "\n---< backtrace of Ruby side >-----\n" + 
                _toUTF8(e.backtrace.join("\n")) + 
                "\n---< backtrace of Tk side >-------"
          msg.instance_variable_set(:@encoding, 'utf-8')
        rescue Exception
          msg = e.class.inspect + ': ' + e.message + "\n" + 
                "\n---< backtrace of Ruby side >-----\n" + 
                e.backtrace.join("\n") + 
                "\n---< backtrace of Tk side >-------"
        end
        fail(e, msg)
      end
=begin
      begin
        raise 'check backtrace'
      rescue
        # ignore backtrace before 'callback'
        pos = -($!.backtrace.size)
      end
      begin
        _get_eval_string(TkVar_CB_TBL[name1].trace_callback(name2,op))
      rescue
        trace = $!.backtrace
        raise $!, "\n#{trace[0]}: #{$!.message} (#{$!.class})\n" + 
                  "\tfrom #{trace[1..pos].join("\n\tfrom ")}"
      end
=end
    else
      ''
    end
  end

  def self.new_hash(val = {})
    if val.kind_of?(Hash)
      self.new(val)
    else
      fail ArgumentError, 'Hash is expected'
    end
  end

  #
  # default_value is available only when the variable is an assoc array. 
  #
  def default_value(val=nil, &b)
    if b
      @def_default = :proc
      @default_val = proc(&b)
    else
      @def_default = :val
      @default_val = val
    end
    self
  end
  def set_default_value(val)
    @def_default = :val
    @default_val = val
    self
  end
  alias default_value= set_default_value
  def default_proc(cmd = Proc.new)
    @def_default = :proc
    @default_val = cmd
    self
  end

  def undef_default
    @default_val = nil
    @def_default = false
    self
  end

  def default_value_type
    @type
  end
  def default_element_value_type(idxs)
    if idxs.kind_of?(Array)
      index = idxs.collect{|idx| _get_eval_string(idx, true)}.join(',')
    else
      index = _get_eval_string(idxs, true)
    end
    @element_type[index]
  end

  def _set_default_value_type_core(type, idxs)
    if type.kind_of?(Class)
      if type == NilClass
        type = nil
      elsif type == Numeric
        type = :numeric
      elsif type == TrueClass || type == FalseClass
        type = :bool
      elsif type == String
        type = :string
      elsif type == Symbol
        type = :symbol
      elsif type == Array
        type = :list
      elsif type <= TkVariable
        type = :variable
      elsif type <= TkWindow
        type = :window
      elsif TkComm._callback_entry_class?(type)
        type = :procedure
      else
        type = nil
      end
    else
      case(type)
      when nil
        type = nil
      when :numeric, 'numeric'
        type = :numeric
      when true, false, :bool, 'bool'
        type = :bool
      when :string, 'string'
        type = :string
      when :symbol, 'symbol'
        type = :symbol
      when :list, 'list'
        type = :list
      when :numlist, 'numlist'
        type = :numlist
      when :variable, 'variable'
        type = :variable
      when :window, 'window'
        type = :window
      when :procedure, 'procedure'
        type = :procedure
      else
        return _set_default_value_type_core(type.class, idxs)
      end
    end
    if idxs
      if idxs.kind_of?(Array)
        index = idxs.collect{|idx| _get_eval_string(idx, true)}.join(',')
      else
        index = _get_eval_string(idxs, true)
      end
      @element_type[index] = type
    else
      @type = type
    end
    type
  end
  private :_set_default_value_type_core

  def set_default_value_type(type)
    _set_default_value_type_core(type, nil)
    self
  end
  alias default_value_type= set_default_value_type

  def set_default_element_value_type(idxs, type)
    _set_default_value_type_core(type, idxs)
    self
  end

  def _to_default_type(val, idxs = nil)
    if idxs
      if idxs.kind_of?(Array)
        index = idxs.collect{|idx| _get_eval_string(idx, true)}.join(',')
      else
        index = _get_eval_string(idxs, true)
      end
      type = @element_type[index]
    else
      type = @type
    end
    return val unless type
    if val.kind_of?(Hash)
      val.keys.each{|k| val[k] = _to_default_type(val[k], idxs) }
      val
    else
      begin
        case(type)
        when :numeric
          number(val)
        when :bool
          TkComm.bool(val)
        when :string
          val
        when :symbol
          val.intern
        when :list
          tk_split_simplelist(val)
        when :numlist
          tk_split_simplelist(val).collect!{|v| number(v)}
        when :variable
          TkVarAccess.new(val)
        when :window
          TkComm.window(val)
        when :procedure
          TkComm.procedure(val)
        else
          val
        end
      rescue
        val
      end
    end
  end
  private :_to_default_type

  def _to_default_element_type(idxs, val)
    _to_default_type(val, idxs)
  end
  private :_to_default_element_type

  def initialize(val="", type=nil)
    # @id = Tk_VARIABLE_ID.join('')
    @id = Tk_VARIABLE_ID.join(TkCore::INTERP._ip_id_)
    Tk_VARIABLE_ID[1].succ!
    TkVar_ID_TBL[@id] = self

    @var  = @id
    @elem = nil

    @def_default = false
    @default_val = nil

    @trace_var  = nil
    @trace_elem = nil
    @trace_opts = nil

    @type = nil
    var = self
    @element_type = Hash.new{|k,v| var.default_value_type }

    self.default_value_type = type

    begin
      INTERP._unset_global_var(@id)
    rescue
    end

    # teach Tk-ip that @id is global var
    INTERP._invoke_without_enc('global', @id)
    #INTERP._invoke('global', @id)

    # create and init
    if val.kind_of?(Hash)
      # assoc-array variable
      self[''] = 0
      self.clear
    end
    self.value = val

=begin
    if val == []
      # INTERP._eval(format('global %s; set %s(0) 0; unset %s(0)', 
      #                     @id, @id, @id))
    elsif val.kind_of?(Array)
      a = []
      # val.each_with_index{|e,i| a.push(i); a.push(array2tk_list(e))}
      # s = '"' + a.join(" ").gsub(/[\[\]$"]/, '\\\\\&') + '"'
      val.each_with_index{|e,i| a.push(i); a.push(e)}
      #s = '"' + array2tk_list(a).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + array2tk_list(a).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; array set %s %s', @id, @id, s))
    elsif  val.kind_of?(Hash)
      #s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
      #             .gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
                   .gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; array set %s %s', @id, @id, s))
    else
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; set %s %s', @id, @id, s))
    end
=end
=begin
    if  val.kind_of?(Hash)
      #s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
      #             .gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
                   .gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; array set %s %s', @id, @id, s))
    else
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
    end
=end
  end

  def wait(on_thread = false, check_root = false)
    if $SAFE >= 4
      fail SecurityError, "can't wait variable at $SAFE >= 4"
    end
    on_thread &= (Thread.list.size != 1)
    if on_thread
      if check_root
        INTERP._thread_tkwait('variable', @id)
      else
        INTERP._thread_vwait(@id)
      end
    else 
      if check_root
        INTERP._invoke_without_enc('tkwait', 'variable', @id)
      else
        INTERP._invoke_without_enc('vwait', @id)
      end
    end
  end
  def eventloop_wait(check_root = false)
    wait(false, check_root)
  end
  def thread_wait(check_root = false)
    wait(true, check_root)
  end
  def tkwait(on_thread = true)
    wait(on_thread, true)
  end
  def eventloop_tkwait
    wait(false, true)
  end
  def thread_tkwait
    wait(true, true)
  end

  def id
    @id
  end

  def ref(*idxs)
    # "#{@id}(#{idxs.collect{|idx| _get_eval_string(idx)}.join(',')})"
    TkVarAccess.new("#{@id}(#{idxs.collect{|idx| _get_eval_string(idx)}.join(',')})")
  end

  def is_hash?
    #ITNERP._eval("global #{@id}; array exist #{@id}") == '1'
    INTERP._invoke_without_enc('global', @id)
    # INTERP._invoke_without_enc('array', 'exist', @id) == '1'
    TkComm.bool(INTERP._invoke_without_enc('array', 'exist', @id))
  end

  def is_scalar?
    ! is_hash?
  end

  def exist?(*elems)
    INTERP._invoke_without_enc('global', @id)
    if elems.empty?
      TkComm.bool(tk_call('info', 'exist', @id))
    else
      # array
      index = elems.collect{|idx| _get_eval_string(idx, true)}.join(',')
      TkComm.bool(tk_call('info', 'exist', "#{@id}")) && 
        TkComm.bool(tk_call('info', 'exist', "#{@id}(#{index})"))
    end
  end

  def keys
    if (is_scalar?)
      fail RuntimeError, 'cannot get keys from a scalar variable'
    end
    #tk_split_simplelist(INTERP._eval("global #{@id}; array get #{@id}"))
    INTERP._invoke_without_enc('global', @id)
    #tk_split_simplelist(INTERP._fromUTF8(INTERP._invoke_without_enc('array', 'names', @id)))
    tk_split_simplelist(INTERP._invoke_without_enc('array', 'names', @id), 
                        false, true)
  end

  def size
    INTERP._invoke_without_enc('global', @id)
    TkComm.number(INTERP._invoke_without_enc('array', 'size', @id))
  end

  def clear
    if (is_scalar?)
      fail RuntimeError, 'cannot clear a scalar variable'
    end
    keys.each{|k| unset(k)}
    self
  end

  def update(hash)
    if (is_scalar?)
      fail RuntimeError, 'cannot update a scalar variable'
    end
    hash.each{|k,v| self[k] = v}
    self
  end

unless const_defined?(:USE_TCLs_SET_VARIABLE_FUNCTIONS)
  USE_TCLs_SET_VARIABLE_FUNCTIONS = true
end

if USE_TCLs_SET_VARIABLE_FUNCTIONS
  ###########################################################################
  # use Tcl function version of set tkvariable
  ###########################################################################

  def _value
    #if INTERP._eval("global #{@id}; array exist #{@id}") == '1'
    INTERP._invoke_without_enc('global', @id)
    # if INTERP._invoke('array', 'exist', @id) == '1'
    if TkComm.bool(INTERP._invoke('array', 'exist', @id))
      #Hash[*tk_split_simplelist(INTERP._eval("global #{@id}; array get #{@id}"))]
      Hash[*tk_split_simplelist(INTERP._invoke('array', 'get', @id))]
    else
      _fromUTF8(INTERP._get_global_var(@id))
    end
  end

  def value=(val)
    val = val._value if !@type && @type != :variable && val.kind_of?(TkVariable)
    if val.kind_of?(Hash)
      self.clear
      val.each{|k, v|
        #INTERP._set_global_var2(@id, _toUTF8(_get_eval_string(k)), 
        #                       _toUTF8(_get_eval_string(v)))
        INTERP._set_global_var2(@id, _get_eval_string(k, true), 
                                _get_eval_string(v, true))
      }
      self.value
#    elsif val.kind_of?(Array)
=begin
      INTERP._set_global_var(@id, '')
      val.each{|v|
        #INTERP._set_variable(@id, _toUTF8(_get_eval_string(v)), 
        INTERP._set_variable(@id, _get_eval_string(v, true), 
                             TclTkLib::VarAccessFlag::GLOBAL_ONLY   | 
                             TclTkLib::VarAccessFlag::LEAVE_ERR_MSG |
                             TclTkLib::VarAccessFlag::APPEND_VALUE  | 
                             TclTkLib::VarAccessFlag::LIST_ELEMENT)
      }
      self.value
=end
#      _fromUTF8(INTERP._set_global_var(@id, array2tk_list(val, true)))
    else
      #_fromUTF8(INTERP._set_global_var(@id, _toUTF8(_get_eval_string(val))))
      _fromUTF8(INTERP._set_global_var(@id, _get_eval_string(val, true)))
    end
  end

  def _element_value(*idxs)
    index = idxs.collect{|idx| _get_eval_string(idx, true)}.join(',')
    begin
      _fromUTF8(INTERP._get_global_var2(@id, index))
    rescue => e
      case @def_default
      when :proc
        @default_val.call(self, *idxs)
      when :val
        @default_val
      else
        fail e
      end
    end
    #_fromUTF8(INTERP._get_global_var2(@id, index))
    #_fromUTF8(INTERP._get_global_var2(@id, _toUTF8(_get_eval_string(index))))
    #_fromUTF8(INTERP._get_global_var2(@id, _get_eval_string(index, true)))
  end

  def []=(*args)
    val = args.pop
    type = default_element_value_type(args)
    val = val._value if !type && type != :variable && val.kind_of?(TkVariable)
    index = args.collect{|idx| _get_eval_string(idx, true)}.join(',')
    _fromUTF8(INTERP._set_global_var2(@id, index, _get_eval_string(val, true)))
    #_fromUTF8(INTERP._set_global_var2(@id, _toUTF8(_get_eval_string(index)), 
    #                                 _toUTF8(_get_eval_string(val))))
    #_fromUTF8(INTERP._set_global_var2(@id, _get_eval_string(index, true), 
    #                                 _get_eval_string(val, true)))
  end

  def unset(*elems)
    if elems.empty?
      INTERP._unset_global_var(@id)
    else
      index = elems.collect{|idx| _get_eval_string(idx, true)}.join(',')
      INTERP._unset_global_var2(@id, index)
    end
  end
  alias remove unset

else
  ###########################################################################
  # use Ruby script version of set tkvariable (traditional methods)
  ###########################################################################

  def _value
    begin
      INTERP._eval(Kernel.format('global %s; set %s', @id, @id))
      #INTERP._eval(Kernel.format('set %s', @id))
      #INTERP._invoke_without_enc('set', @id)
    rescue
      if INTERP._eval(Kernel.format('global %s; array exists %s', 
                            @id, @id)) != "1"
      #if INTERP._eval(Kernel.format('array exists %s', @id)) != "1"
      #if INTERP._invoke_without_enc('array', 'exists', @id) != "1"
        fail
      else
        Hash[*tk_split_simplelist(INTERP._eval(Kernel.format('global %s; array get %s', @id, @id)))]
        #Hash[*tk_split_simplelist(_fromUTF8(INTERP._invoke_without_enc('array', 'get', @id)))]
      end
    end
  end

  def value=(val)
    val = val._value if !@type && @type != :variable && val.kind_of?(TkVariable)
    begin
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
      #INTERP._eval(Kernel.format('set %s %s', @id, s))
      #_fromUTF8(INTERP._invoke_without_enc('set', @id, _toUTF8(s)))
    rescue
      if INTERP._eval(Kernel.format('global %s; array exists %s', 
                            @id, @id)) != "1"
      #if INTERP._eval(Kernel.format('array exists %s', @id)) != "1"
      #if INTERP._invoke_without_enc('array', 'exists', @id) != "1"
        fail
      else
        if val == []
          INTERP._eval(Kernel.format('global %s; unset %s; set %s(0) 0; unset %s(0)', @id, @id, @id, @id))
          #INTERP._eval(Kernel.format('unset %s; set %s(0) 0; unset %s(0)', 
          #                          @id, @id, @id))
          #INTERP._invoke_without_enc('unset', @id)
          #INTERP._invoke_without_enc('set', @id+'(0)', 0)
          #INTERP._invoke_without_enc('unset', @id+'(0)')
        elsif val.kind_of?(Array)
          a = []
          val.each_with_index{|e,i| a.push(i); a.push(array2tk_list(e, true))}
          #s = '"' + a.join(" ").gsub(/[\[\]$"]/, '\\\\\&') + '"'
          s = '"' + a.join(" ").gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
          INTERP._eval(Kernel.format('global %s; unset %s; array set %s %s', 
                                     @id, @id, @id, s))
          #INTERP._eval(Kernel.format('unset %s; array set %s %s', 
          #                          @id, @id, s))
          #INTERP._invoke_without_enc('unset', @id)
          #_fromUTF8(INTERP._invoke_without_enc('array','set', @id, _toUTF8(s)))
        elsif  val.kind_of?(Hash)
          #s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
          #                      .gsub(/[\[\]$"]/, '\\\\\&') + '"'
          s = '"' + val.to_a.collect{|e| array2tk_list(e, true)}.join(" ")\
                                .gsub(/[\[\]$\\"]/, '\\\\\&') + '"'
          INTERP._eval(Kernel.format('global %s; unset %s; array set %s %s', 
                                     @id, @id, @id, s))
          #INTERP._eval(Kernel.format('unset %s; array set %s %s', 
          #                          @id, @id, s))
          #INTERP._invoke_without_enc('unset', @id)
          #_fromUTF8(INTERP._invoke_without_enc('array','set', @id, _toUTF8(s)))
        else
          fail
        end
      end
    end
  end

  def _element_value(*idxs)
    index = idxs.collect{|idx| _get_eval_string(idx)}.join(',')
    begin
      INTERP._eval(Kernel.format('global %s; set %s(%s)', @id, @id, index))
    rescue => e
      case @def_default
      when :proc
        @default_val.call(self, *idxs)
      when :val
        @default_val
      else
        fail e
      end
    end
    #INTERP._eval(Kernel.format('global %s; set %s(%s)', @id, @id, index))
    #INTERP._eval(Kernel.format('global %s; set %s(%s)', 
    #                           @id, @id, _get_eval_string(index)))
    #INTERP._eval(Kernel.format('set %s(%s)', @id, _get_eval_string(index)))
    #INTERP._eval('set ' + @id + '(' + _get_eval_string(index) + ')')
  end

  def []=(*args)
    val = args.pop
    type = default_element_value_type(args)
    val = val._value if !type && type != :variable && val.kind_of?(TkVariable)
    index = args.collect{|idx| _get_eval_string(idx)}.join(',')
    INTERP._eval(Kernel.format('global %s; set %s(%s) %s', @id, @id, 
                              index, _get_eval_string(val)))
    #INTERP._eval(Kernel.format('global %s; set %s(%s) %s', @id, @id, 
    #                          _get_eval_string(index), _get_eval_string(val)))
    #INTERP._eval(Kernel.format('set %s(%s) %s', @id, 
    #                          _get_eval_string(index), _get_eval_string(val)))
    #INTERP._eval('set ' + @id + '(' + _get_eval_string(index) + ') ' + 
    #            _get_eval_string(val))
  end

  def unset(*elems)
    if elems.empty?
      INTERP._eval(Kernel.format('global %s; unset %s', @id, @id))
      #INTERP._eval(Kernel.format('unset %s', @id))
      #INTERP._eval('unset ' + @id)
    else
      index = elems.collect{|idx| _get_eval_string(idx, true)}.join(',')
      INTERP._eval(Kernel.format('global %s; unset %s(%s)', @id, @id, index))
      #INTERP._eval(Kernel.format('global %s; unset %s(%s)', 
      #                           @id, @id, _get_eval_string(elem)))
      #INTERP._eval(Kernel.format('unset %s(%s)', @id, tk_tcl2ruby(elem)))
      #INTERP._eval('unset ' + @id + '(' + _get_eval_string(elem) + ')')
    end
  end
  alias remove unset

end

  protected :_value, :_element_value

  def value
    _to_default_type(_value)
  end

  def [](*idxs)
    _to_default_element_type(idxs, _element_value(*idxs))
  end

  def set_value(val)
    self.value = val
    self
  end

  def set_element_value(idxs, val)
    if idxs.kind_of?(Array)
      self[*idxs]=val
    else
      self[idxs]=val
    end
    self
  end

  def set_value_type(val)
    self.default_value_type = val.class
    self.value = val
    self
  end

  alias value_type= set_value_type

  def set_element_value_type(idxs, val)
    self.set_default_element_value_type(idxs, val.class)
    if idxs.kind_of?(Array)
      self[*idxs]=val
    else
      self[idxs]=val
    end
    self
  end

  def numeric
    number(_value)
  end
  def numeric_element(*idxs)
    number(_element_value(*idxs))
  end
  def set_numeric(val)
    case val
    when Numeric
      self.value=(val)
    when TkVariable
      self.value=(val.numeric)
    else
      raise ArgumentError, "Numeric is expected"
    end
    self
  end
  alias numeric= set_numeric
  def set_numeric_element(idxs, val)
    case val
    when Numeric
      val
    when TkVariable
      val = val.numeric
    else
      raise ArgumentError, "Numeric is expected"
    end
    if idxs.kind_of?(Array)
      self[*idxs]=val
    else
      self[idxs]=val
    end
    self
  end
  def set_numeric_type(val)
    @type = :numeric
    self.numeric=(val)
    self
  end
  alias numeric_type= set_numeric_type
  def set_numeric_element_type(idxs, val)
    self.set_default_element_value_type(idxs, :numeric)
    self.set_numeric_element(idxs, val)
  end

  def bool
    TkComm.bool(_value)
=begin
    # see Tcl_GetBoolean man-page
    case _value.downcase
    when '0', 'false', 'no', 'off'
      false
    else
      true
    end
=end
  end
  def bool_element(*idxs)
    TkComm.bool(_element_value(*idxs))
  end
  def set_bool(val)
    if ! val
      self.value = '0'
    else
      case val.to_s.downcase
      when 'false', '0', 'no', 'off'
        self.value = '0'
      else
        self.value = '1'
      end
    end
    self
  end
  alias bool= set_bool
  def set_bool_element(idxs, val)
    if ! val
      val = '0'
    else
      case val.to_s.downcase
      when 'false', '0', 'no', 'off'
        val = '0'
      else
        val = '1'
      end
    end
    if idxs.kind_of?(Array)
      self[*idxs]=val
    else
      self[idxs]=val
    end
    self
  end
  def set_bool_type(val)
    @type = :bool
    self.bool=(val)
    self
  end
  alias bool_type= set_bool_type
  def set_bool_element_type(idxs, val)
    self.set_default_element_value_type(idxs, :bool)
    self.set_bool_element(idxs, val)
  end

  def variable
    # keeps a Tcl's variable name
    TkVarAccess.new(self._value)
  end
  def variable_element(*idxs)
    TkVarAccess.new(_element_value(*idxs))
  end
  def set_variable(var)
    var = var.id if var.kind_of?(TkVariable)
    self.value = var
    self
  end
  alias variable= set_variable
  def set_variable_element(idxs, var)
    var = var.id if var.kind_of?(TkVariable)
    if idxs.kind_of?(Array)
      self[*idxs]=var
    else
      self[idxs]=var
    end
    self
  end
  def set_variable_type(var)
    @type = :variable
    var = var.id if var.kind_of?(TkVariable)
    self.value = var
    self
  end
  alias variable_type= set_variable_type
  def set_variable_element_type(idxs, var)
    self.set_default_element_value_type(idxs, :variable)
    self.set_variable_element(idxs, var)
  end

  def window
    TkComm.window(self._value)
  end
  def window_element(*idxs)
    TkComm.window(_element_value(*idxs))
  end
  def set_window(win)
    win = win._value if win.kind_of?(TkVariable)
    self.value = win
    self
  end
  alias window= set_window
  def set_window_element(idxs, win)
    win = win._value if win.kind_of?(TkVariable)
    if idxs.kind_of?(Array)
      self[*idxs]=win
    else
      self[idxs]=win
    end
    self
  end
  def set_window_type(win)
    @type = :window
    self.window=(win)
    self
  end
  alias window_type= set_window_type
  def set_window_element_type(idxs, win)
    self.set_default_element_value_type(idxs, :window)
    self.set_window_element(idxs, win)
  end

  def procedure
    TkComm.procedure(self._value)
  end
  def procedure_element(*idxs)
    TkComm.procedure(_element_value(*idxs))
  end
  def set_procedure(cmd)
    self.value = cmd
    self
  end
  alias procedure= set_procedure
  def set_procedure_element(idxs, cmd)
    cmd = cmd._value if cmd.kind_of?(TkVariable)
    if idxs.kind_of?(Array)
      self[*idxs]=cmd
    else
      self[idxs]=cmd
    end
    self
  end
  def set_procedure_type(cmd)
    @type = :procedure
    self.procedure=(cmd)
    self
  end
  alias procedure_type= set_procedure_type
  def set_procedure_element_type(idxs, cmd)
    self.set_default_element_value_type(idxs, :procedure)
    self.set_proceure_element(idxs, cmd)
  end

  def to_i
    number(_value).to_i
  end
  def element_to_i(*idxs)
    number(_element_value(*idxs)).to_i
  end

  def to_f
    number(_value).to_f
  end
  def element_to_f(*idxs)
    number(_element_value(*idxs)).to_f
  end

  def to_s
    #string(value).to_s
    _value
  end
  alias string to_s
  def element_to_s(*idxs)
    _element_value(*idxs)
  end
  def string_element(*idxs)
    _element_value(*idxs)
  end
  def set_string(val)
    val = val._value if val.kind_of?(TkVariable)
    self.value=val
    self
  end
  alias string= set_string
  def set_string_element(idxs, val)
    val = val._value if val.kind_of?(TkVariable)
    if idxs.kind_of?(Array)
      self[*idxs]=val
    else
      self[idxs]=val
    end
    self
  end
  def set_string_type(val)
    @type = :string
    self.string=(val)
    self
  end
  alias string_type= set_string_type
  def set_string_element_type(idxs, val)
    self.set_default_element_value_type(idxs, :string)
    self.set_string_element(idxs, val)
  end

  def to_sym
    _value.intern
  end
  alias symbol to_sym
  def element_to_sym(*idxs)
    _element_value(*idxs).intern
  end
  alias symbol_element element_to_sym
  def set_symbol(val)
    val = val._value if val.kind_of?(TkVariable)
    self.value=val
    self
  end
  alias symbol= set_symbol
  def set_symbol_element(idxs, val)
    val = val._value if val.kind_of?(TkVariable)
    if idxs.kind_of?(Array)
      self[*idxs]=val
    else
      self[idxs]=val
    end
    self
  end
  def set_symbol_type(val)
    @type = :symbol
    self.value=(val)
    self
  end
  alias symbol_type= set_symbol_type
  def set_symbol_element_type(idxs, val)
    self.set_default_element_value_type(idxs, :symbol)
    self.set_symbol_element(idxs, val)
  end

  def list
    #tk_split_list(value)
    tk_split_simplelist(_value)
  end
  alias to_a list
  def list_element(*idxs)
    tk_split_simplelist(_element_value(*idxs))
  end
  alias element_to_a list_element

  def numlist
    list.collect!{|val| number(val)}
  end
  def numlist_element(*idxs)
    list_element(*idxs).collect!{|val| number(val)}
  end

  def set_list(val)
    case val
    when Array
      self.value=(val)
    when TkVariable
      self.value=(val.list)
    else
      raise ArgumentError, "Array is expected"
    end
    self
  end
  alias list= set_list

  alias set_numlist set_list
  alias numlist= set_numlist

  def set_list_element(idxs, val)
    case val
    when Array
      val
    when TkVariable
      val = val.list
    else
      raise ArgumentError, "Array is expected"
    end
    if idxs.kind_of?(Array)
      self[*idxs]=val
    else
      self[idxs]=val
    end
    self
  end
  alias set_numlist_element set_list_element

  def set_list_type(val)
    @type = :list
    self.list=(val)
    self
  end
  alias list_type= set_list_type
  def set_list_element_type(idxs, val)
    self.set_default_element_value_type(idxs, :list)
    self.set_list_element(idxs, val)
  end
  def set_numlist_type(val)
    @type = :numlist
    self.numlist=(val)
    self
  end
  alias numlist_type= set_numlist_type
  def set_numlist_element_type(idxs, val)
    self.set_default_element_value_type(idxs, :numlist)
    self.set_numlist_element(idxs, val)
  end

  def lappend(*elems)
    tk_call('lappend', @id, *elems)
    self
  end
  def element_lappend(idxs, *elems)
    if idxs.kind_of?(Array)
      idxs = idxs.collect{|idx| _get_eval_string(idx, true)}.join(',')
    end
    tk_call('lappend', "#{@id}(#{idxs})", *elems)
    self
  end

  def lindex(idx)
    tk_call('lindex', self._value, idx)
  end
  alias lget lindex
  def element_lindex(elem_idxs, idx)
    if elem_idxs.kind_of?(Array)
      val = _element_value(*elem_idxs)
    else
      val = _element_value(elem_idxs)
    end
    tk_call('lindex', val, idx)
  end
  alias element_lget element_lindex

  def lget_i(idx)
    number(lget(idx)).to_i
  end
  def element_lget_i(elem_idxs, idx)
    number(element_lget(elem_idxs, idx)).to_i
  end

  def lget_f(idx)
    number(lget(idx)).to_f
  end
  def element_lget_f(elem_idxs, idx)
    number(element_lget(elem_idxs, idx)).to_f
  end

  def lset(idx, val)
    tk_call('lset', @id, idx, val)
    self
  end
  def element_lset(elem_idxs, idx, val)
    if elem_idxs.kind_of?(Array)
      idxs = elem_idxs.collect{|i| _get_eval_string(i, true)}.join(',')
    end
    tk_call('lset', "#{@id}(#{idxs})", idx, val)
    self
  end

  def inspect
    #Kernel.format "#<TkVariable: %s>", @id
    '#<TkVariable: ' + @id + '>'
  end

  def coerce(other)
    case other
    when TkVariable
      [other._value, self._value]
    when String
      [other, self.to_s]
    when Symbol
      [other, self.to_sym]
    when Integer
      [other, self.to_i]
    when Float
      [other, self.to_f]
    when Array
      [other, self.to_a]
    else
      [other, self._value]
    end
  end

  def &(other)
    if other.kind_of?(Array)
      self.to_a & other.to_a
    else
      self.to_i & other.to_i
    end
  end
  def |(other)
    if other.kind_of?(Array)
      self.to_a | other.to_a
    else
      self.to_i | other.to_i
    end
  end
  def +(other)
    case other
    when Array
      self.to_a + other
    when String
      self._value + other
    else
      begin
        number(self._value) + other
      rescue
        self._value + other.to_s
      end
    end
  end
  def -(other)
    if other.kind_of?(Array)
      self.to_a - other
    else
      number(self._value) - other
    end
  end
  def *(other)
    num_or_str(self._value) * other.to_i
    #begin
    #  number(self._value) * other
    #rescue
    #  self._value * other
    #end
  end
  def /(other)
    number(self._value) / other
  end
  def %(other)
    num_or_str(self._value) % other.to_i
    #begin
    #  number(self._value) % other
    #rescue
    #  self._value % other
    #end
  end
  def **(other)
    number(self._value) ** other
  end
  def =~(other)
    self._value =~ other
  end

  def ==(other)
    case other
    when TkVariable
      #self.equal?(other)
      self._value == other._value
    when String
      self.to_s == other
    when Symbol
      self.to_sym == other
    when Integer
      self.to_i == other
    when Float
      self.to_f == other
    when Array
      self.to_a == other
    when Hash
      # false if self is not an assoc array
      self._value == other
    else
      # false
      self._value == _get_eval_string(other)
    end
  end

  def zero?
    numeric.zero?
  end
  def nonzero?
    !(numeric.zero?)
  end

  def <=>(other)
    if other.kind_of?(TkVariable)
      begin
        val = other.numeric
        other = val
      rescue
        other = other._value
      end
    elsif other.kind_of?(Numeric)
      begin
        return self.numeric <=> other
      rescue
        return self._value <=> other.to_s
      end
    elsif other.kind_of?(Array)
      return self.list <=> other
    else
      return self._value <=> other
    end
  end

  def to_eval
    @id
  end

  def trace_callback(elem, op)
    if @trace_var.kind_of? Array
      @trace_var.each{|m,e| e.call(self,elem,op) if m.index(op)}
    end
    if elem.kind_of?(String) && elem != ''
      if @trace_elem.kind_of?(Hash) && @trace_elem[elem].kind_of?(Array)
        @trace_elem[elem].each{|m,e| e.call(self,elem,op) if m.index(op)}
      end
    end
  end

  def trace(opts, cmd = Proc.new)
    @trace_var = [] if @trace_var == nil
    #opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    opts = opts.to_s
    opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    @trace_var.unshift([opts,cmd])
    if @trace_opts == nil
      TkVar_CB_TBL[@id] = self
      @trace_opts = opts.dup
      Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 
                             'rb_var ' << @id)
=begin
      if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
        # TCL_VERSION >= 8.4
        Tk.tk_call_without_enc('trace', 'add', 'variable', 
                               @id, @trace_opts, 'rb_var')
      else
        # TCL_VERSION <= 8.3
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 'rb_var')
      end
=end
    else
      newopts = @trace_opts.dup
      #opts.each_byte{|c| newopts += c.chr unless newopts.index(c)}
      opts.each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
      if newopts != @trace_opts
        Tk.tk_call_without_enc('trace', 'vdelete', @id, @trace_opts, 
                               'rb_var ' << @id)
        @trace_opts.replace(newopts)
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 
                               'rb_var ' << @id)
=begin
        if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
          # TCL_VERSION >= 8.4
          Tk.tk_call_without_enc('trace', 'remove', 'variable', 
                                 @id, @trace_opts, 'rb_var')
          @trace_opts.replace(newopts)
          Tk.tk_call_without_enc('trace', 'add', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        else
          # TCL_VERSION <= 8.3
          Tk.tk_call_without_enc('trace', 'vdelete', 
                                 @id, @trace_opts, 'rb_var')
          @trace_opts.replace(newopts)
          Tk.tk_call_without_enc('trace', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        end
=end
      end
    end
    self
  end

  def trace_element(elem, opts, cmd = Proc.new)
    if @elem
      fail(RuntimeError, 
           "invalid for a TkVariable which denotes an element of Tcl's array")
    end
    @trace_elem = {} if @trace_elem == nil
    @trace_elem[elem] = [] if @trace_elem[elem] == nil
    opts = opts.to_s
    opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    @trace_elem[elem].unshift([opts,cmd])
    if @trace_opts == nil
      TkVar_CB_TBL[@id] = self
      @trace_opts = opts.dup
      Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 
                             'rb_var ' << @id)
=begin
      if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
        # TCL_VERSION >= 8.4
        Tk.tk_call_without_enc('trace', 'add', 'variable', 
                               @id, @trace_opts, 'rb_var')
      else
        # TCL_VERSION <= 8.3
        Tk.tk_call_without_enc('trace', 'variable', 
                               @id, @trace_opts, 'rb_var')
      end
=end
    else
      newopts = @trace_opts.dup
      # opts.each_byte{|c| newopts += c.chr unless newopts.index(c)}
      opts.each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
      if newopts != @trace_opts
        Tk.tk_call_without_enc('trace', 'vdelete', @id, @trace_opts, 
                               'rb_var ' << @id)
        @trace_opts.replace(newopts)
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 
                               'rb_var ' << @id)
=begin
        if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
          # TCL_VERSION >= 8.4
          Tk.tk_call_without_enc('trace', 'remove', 'variable', 
                                 @id, @trace_opts, 'rb_var')
          @trace_opts.replace(newopts)
          Tk.tk_call_without_enc('trace', 'add', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        else
          # TCL_VERSION <= 8.3
          Tk.tk_call_without_enc('trace', 'vdelete', 
                                 @id, @trace_opts, 'rb_var')
          @trace_opts.replace(newopts)
          Tk.tk_call_without_enc('trace', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        end
=end
      end
    end
    self
  end

  def trace_vinfo
    return [] unless @trace_var
    @trace_var.dup
  end

  def _trace_vinfo_for_element(elem)
    if @elem
      fail(RuntimeError, 
           "invalid for a TkVariable which denotes an element of Tcl's array")
    end
    return [] unless @trace_elem
    return [] unless @trace_elem[elem]
    @trace_elem[elem].dup
  end

  def trace_vdelete(opts,cmd)
    return self unless @trace_var.kind_of? Array
    opts = opts.to_s
    opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    idx = -1
    newopts = ''
    @trace_var.each_with_index{|e,i| 
      if idx < 0 && e[0] == opts && e[1] == cmd
        idx = i
        next
      end
      # e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
      e[0].each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
    }
    if idx >= 0
      @trace_var.delete_at(idx) 
    else
      return self
    end

    @trace_elem.each{|elem|
      @trace_elem[elem].each{|e|
        # e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
        e[0].each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
      }
    }

    newopts = newopts.to_s
    newopts = ['r','w','u'].find_all{|c| newopts.index(c)}.join('')
    if newopts != @trace_opts
      Tk.tk_call_without_enc('trace', 'vdelete', @id, @trace_opts, 
                             'rb_var ' << @id)
=begin
      if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
        # TCL_VERSION >= 8.4
        Tk.tk_call_without_enc('trace', 'remove', 'variable', 
                               @id, @trace_opts, 'rb_var')
      else
        # TCL_VERSION <= 8.3
        Tk.tk_call_without_enc('trace', 'vdelete', 
                               @id, @trace_opts, 'rb_var')
      end
=end
      @trace_opts.replace(newopts)
      if @trace_opts != ''
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 
                               'rb_var ' << @id)
=begin
        if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
          # TCL_VERSION >= 8.4
          Tk.tk_call_without_enc('trace', 'add', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        else
          # TCL_VERSION <= 8.3
          Tk.tk_call_without_enc('trace', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        end
=end
      end
    end

    self
  end

  def trace_vdelete_for_element(elem,opts,cmd)
    if @elem
      fail(RuntimeError, 
           "invalid for a TkVariable which denotes an element of Tcl's array")
    end
    return self unless @trace_elem.kind_of? Hash
    return self unless @trace_elem[elem].kind_of? Array
    opts = opts.to_s
    opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    idx = -1
    @trace_elem[elem].each_with_index{|e,i| 
      if idx < 0 && e[0] == opts && e[1] == cmd
        idx = i
        next
      end
    }
    if idx >= 0
      @trace_elem[elem].delete_at(idx)
    else
      return self
    end

    newopts = ''
    @trace_var.each{|e| 
      # e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
      e[0].each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
    }
    @trace_elem.each{|elem|
      @trace_elem[elem].each{|e|
        # e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
        e[0].each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
      }
    }

    newopts = newopts.to_s
    newopts = ['r','w','u'].find_all{|c| newopts.index(c)}.join('')
    if newopts != @trace_opts
      Tk.tk_call_without_enc('trace', 'vdelete', @id, @trace_opts, 
                             'rb_var ' << @id)
=begin
      if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
        # TCL_VERSION >= 8.4
        Tk.tk_call_without_enc('trace', 'remove', 'variable', 
                               @id, @trace_opts, 'rb_var')
      else
        # TCL_VERSION <= 8.3
        Tk.tk_call_without_enc('trace', 'vdelete', 
                               @id, @trace_opts, 'rb_var')
      end
=end
      @trace_opts.replace(newopts)
      if @trace_opts != ''
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 
                               'rb_var ' << @id)
=begin
        if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
          # TCL_VERSION >= 8.4
          Tk.tk_call_without_enc('trace', 'add', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        else
          # TCL_VERSION <= 8.3
          Tk.tk_call_without_enc('trace', 'variable', @id, 
                                 @trace_opts, 'rb_var')
        end
=end
      end
    end

    self
  end
end

class TkVarAccess<TkVariable
  def self.new(name, *args)
    return TkVar_ID_TBL[name] if TkVar_ID_TBL[name]
    super(name, *args)
  end

  def self.new_hash(name, *args)
    return TkVar_ID_TBL[name] if TkVar_ID_TBL[name]
    INTERP._invoke_without_enc('global', name)
    if args.empty? && INTERP._invoke_without_enc('array', 'exist', name) == '0'
      self.new(name, {})  # force creating
    else
      self.new(name, *args)
    end
  end

  def initialize(varname, val=nil)
    @id = varname
    TkVar_ID_TBL[@id] = self

    @var  = @id
    @elem = nil

    @def_default = false
    @default_val = nil

    @trace_var  = nil
    @trace_elem = nil
    @trace_opts = nil

    @type = nil
    var = self
    @element_type = Hash.new{|k,v| var.default_value_type }

    # is an element?
    if @id =~ /^([^(]+)\((.+)\)$/
      # is an element --> var == $1, elem == $2
      @var  = $1
      @elem = $2
    end

    # teach Tk-ip that @id is global var
    INTERP._invoke_without_enc('global', @var)
=begin
    begin
      INTERP._invoke_without_enc('global', @id)
    rescue => e
      if @id =~ /^(.+)\([^()]+\)$/
        # is an element --> varname == $1
        INTERP._invoke_without_enc('global', $1)
      else
        fail e
      end
    end
=end

    if val
      if val.kind_of?(Hash)
        # assoc-array variable
        self[''] = 0
        self.clear
      end
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"' #"
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"' #"
      #INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
      #INTERP._set_global_var(@id, _toUTF8(_get_eval_string(val)))
      self.value = val
    end
  end
end

module Tk
  begin
    INTERP._invoke_without_enc('global', 'auto_path')
    auto_path = INTERP._invoke('set', 'auto_path')
  rescue => e
    begin
      INTERP._invoke_without_enc('global', 'env')
      auto_path = INTERP._invoke('set', 'env(TCLLIBPATH)')
    rescue => e
      auto_path = Tk::LIBRARY
    end
  end

  AUTO_PATH = TkVarAccess.new('auto_path', auto_path)

=begin
  AUTO_OLDPATH = tk_split_simplelist(INTERP._invoke('set', 'auto_oldpath'))
  AUTO_OLDPATH.each{|s| s.freeze}
  AUTO_OLDPATH.freeze
=end

  TCL_PACKAGE_PATH = TkVarAccess.new('tcl_pkgPath')
  PACKAGE_PATH = TCL_PACKAGE_PATH

  TCL_LIBRARY_PATH = TkVarAccess.new('tcl_libPath')
  LIBRARY_PATH = TCL_LIBRARY_PATH

  TCL_PRECISION = TkVarAccess.new('tcl_precision')
end
