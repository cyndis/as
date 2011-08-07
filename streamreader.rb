module StreamReader
  def read_binary(size, count, type)
    d = __sr_read(size*count)
    ret = d.unpack(type*count)
    return ret if ret.length > 1
    return ret[0]
  end
  def read_uint32(n=1)
    return read_binary(4,n,'L')
  end
  def read_uint16(n=1)
    return read_binary(2,n,'S')
  end
  def read_uint8(n=1)
    return read_binary(1,n,'C')
  end
  def read_uint64(n=1)
    return read_binary(8,n,'Q')
  end
  def read_sint64(n=1)
    return read_binary(8,n,'q')
  end
  def read_cstr_fixed(length)
    return __sr_read(length).gsub("\000",'')
  end
  def read_cstr_terminated
    return __sr_gets(0.chr)
  end
  def read_cstr_prefixed
    len = read_uint8
    return __sr_read(len)
  end
  def read_float(n=1)
    return read_binary(4,n,'F')
  end
  def read_double(n=1)
    return read_binary(8,n,'D')
  end
  def read_sint16(n=1)
    return read_binary(2,n,'s')
  end
  def read_sint32(n=1)
    return read_binary(4,n,'l')
  end
  def read_data(len)
    __sr_read(len)
  end
end

module StreamWriter
  def write_binary(values, type)
    d = values.pack(type * values.length)
    __sr_write(d)
  end
  def write_uint32(*args)
    return write_binary(args,'L')
  end
  def write_uint16(*args)
    return write_binary(args,'S')
  end
  def write_uint8(*args)
    return write_binary(args,'C')
  end
  def write_uint64(*args)
    return write_binary(args,'Q')
  end
  def write_sint64(*args)
    return write_binary(args,'q')
  end
  def write_cstr_fixed(str, len)
    return __sr_write(str.ljust(len, 0.chr))
  end
  def write_cstr_terminated(str)
    return __sr_write(str + 0.chr)
  end
  def write_cstr_prefixed(str)
    write_uint8(str.length)
    return __sr_write(str)
  end
  def write_str(str)
    return __sr_write(str)
  end
  def write_float(*args)
    return write_binary(args,'F')
  end
  def write_double(*args)
    return write_binary(args,'D')
  end
  def write_sint16(*args)
    return write_binary(args,'s')
  end
  def write_sint32(*args)
    return write_binary(args,'l')
  end
  def write_data(str)
    return __sr_write(str)
  end
end

class IO
  include StreamReader
  include StreamWriter
  
  def __sr_read(len)
    read(len)
  end
  def __sr_write(str)  
    write(str)
  end
end

require 'stringio'
class StringIO
  include StreamReader
  include StreamWriter
  
  def __sr_read(len)
    read(len)
  end
  def __sr_write(str)  
    write(str)
  end
end
